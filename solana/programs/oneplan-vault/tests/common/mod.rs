#![allow(dead_code)]

use {
    anchor_lang::{
        prelude::Pubkey,
        solana_program::{clock::Clock, instruction::Instruction, system_program},
        AccountDeserialize, InstructionData, ToAccountMetas,
    },
    anchor_spl::associated_token::get_associated_token_address,
    litesvm::{types::FailedTransactionMetadata, LiteSVM},
    litesvm_token::{
        get_spl_account, spl_token, CreateAssociatedTokenAccount, CreateMint, MintTo,
    },
    oneplan_vault::{constants::VAULT_SEED, error::VaultError},
    solana_instruction::error::InstructionError,
    solana_keypair::Keypair,
    solana_message::{Message, VersionedMessage},
    solana_signer::Signer,
    solana_transaction::versioned::VersionedTransaction,
    solana_transaction_error::TransactionError,
};

/// Whole USDC to micro-USDC.
pub fn usdc(n: u64) -> u64 {
    n * 1_000_000
}

/// Net credited to the vault after the 0.1% deposit skim.
pub fn after_fee(amount: u64) -> u64 {
    let fee = amount.saturating_mul(10) / 10_000;
    amount - fee
}

pub fn vault_pda(program_id: &Pubkey, trip_id: u64) -> Pubkey {
    Pubkey::find_program_address(&[VAULT_SEED, &trip_id.to_le_bytes()], program_id).0
}

/// Builds and sends a single-instruction legacy transaction.
pub fn send(
    svm: &mut LiteSVM,
    ix: Instruction,
    payer: &Keypair,
    signers: &[&Keypair],
) -> Result<(), FailedTransactionMetadata> {
    svm.expire_blockhash();
    let blockhash = svm.latest_blockhash();
    let msg = Message::new_with_blockhash(&[ix], Some(&payer.pubkey()), &blockhash);
    let tx = VersionedTransaction::try_new(VersionedMessage::Legacy(msg), signers)
        .expect("failed to sign transaction");
    svm.send_transaction(tx).map(|_| ())
}

pub fn assert_vault_error(res: Result<(), FailedTransactionMetadata>, expected: VaultError) {
    let failure = res.err().expect("expected the instruction to fail");
    let want = u32::from(expected);
    match failure.err {
        TransactionError::InstructionError(_, InstructionError::Custom(got)) => {
            assert_eq!(got, want, "wrong error code");
        }
        other => panic!("expected custom error {want}, got {other:?}"),
    }
}

pub fn warp_seconds(svm: &mut LiteSVM, seconds: i64) {
    let mut clock = svm.get_sysvar::<Clock>();
    clock.unix_timestamp += seconds;
    svm.set_sysvar::<Clock>(&clock);
}

pub fn token_balance(svm: &LiteSVM, ata: &Pubkey) -> u64 {
    let account: spl_token::state::Account =
        get_spl_account(svm, ata).expect("token account not found");
    account.amount
}

pub fn fetch<T: AccountDeserialize>(svm: &LiteSVM, key: &Pubkey) -> T {
    let account = svm.get_account(key).expect("account not found");
    let mut data: &[u8] = &account.data;
    T::try_deserialize(&mut data).expect("failed to deserialize account")
}

pub struct TestMember {
    pub kp: Keypair,
    pub ata: Pubkey,
}

pub struct Ctx {
    pub svm: LiteSVM,
    pub program_id: Pubkey,
    pub server: Keypair,
    pub authority: Keypair,
    pub mint: Pubkey,
    pub vault: Pubkey,
    pub vault_ata: Pubkey,
    pub treasury_ata: Pubkey,
    pub members: Vec<TestMember>,
}

impl Ctx {
    pub fn setup(
        trip_id: u64,
        threshold: u64,
        daily_limit: u64,
        member_count: usize,
        fund_each: u64,
    ) -> Self {
        let program_id = oneplan_vault::id();
        let mut svm = LiteSVM::new();
        let bytes = include_bytes!(concat!(
            env!("CARGO_TARGET_TMPDIR"),
            "/../deploy/oneplan_vault.so"
        ));
        svm.add_program(program_id, bytes).unwrap();

        let server = Keypair::new();
        let authority = Keypair::new();
        svm.airdrop(&server.pubkey(), 100_000_000_000).unwrap();
        svm.airdrop(&authority.pubkey(), 10_000_000_000).unwrap();

        let mint = CreateMint::new(&mut svm, &server)
            .decimals(6)
            .send()
            .expect("create mint");

        let vault = vault_pda(&program_id, trip_id);
        let vault_ata = get_associated_token_address(&vault, &mint);

        let treasury_ata = CreateAssociatedTokenAccount::new(&mut svm, &server, &mint)
            .owner(&server.pubkey())
            .send()
            .expect("create treasury ata");

        let ix = Instruction::new_with_bytes(
            program_id,
            &oneplan_vault::instruction::InitVault {
                trip_id,
                threshold,
                daily_limit,
            }
            .data(),
            oneplan_vault::accounts::InitVault {
                vault,
                vault_ata,
                usdc_mint: mint,
                authority: authority.pubkey(),
                server: server.pubkey(),
                token_program: spl_token::ID,
                associated_token_program: anchor_spl::associated_token::ID,
                system_program: system_program::ID,
            }
            .to_account_metas(None),
        );
        send(&mut svm, ix, &server, &[&server, &authority]).expect("init_vault");

        let mut members = Vec::new();
        for _ in 0..member_count {
            let kp = Keypair::new();
            svm.airdrop(&kp.pubkey(), 10_000_000_000).unwrap();

            let ata = CreateAssociatedTokenAccount::new(&mut svm, &server, &mint)
                .owner(&kp.pubkey())
                .send()
                .expect("create member ata");
            if fund_each > 0 {
                MintTo::new(&mut svm, &server, &mint, &ata, fund_each)
                    .send()
                    .expect("mint to member");
            }

            let ix = Instruction::new_with_bytes(
                program_id,
                &oneplan_vault::instruction::AddMember {}.data(),
                oneplan_vault::accounts::AddMember {
                    vault,
                    owner: kp.pubkey(),
                    authority: authority.pubkey(),
                }
                .to_account_metas(None),
            );
            send(&mut svm, ix, &server, &[&server, &authority]).expect("add_member");

            members.push(TestMember { kp, ata });
        }

        Ctx {
            svm,
            program_id,
            server,
            authority,
            mint,
            vault,
            vault_ata,
            treasury_ata,
            members,
        }
    }

    pub fn deposit(&mut self, index: usize, amount: u64) {
        let kp = self.members[index].kp.insecure_clone();
        let ata = self.members[index].ata;
        let ix = Instruction::new_with_bytes(
            self.program_id,
            &oneplan_vault::instruction::Deposit { amount }.data(),
            oneplan_vault::accounts::Deposit {
                vault: self.vault,
                vault_ata: self.vault_ata,
                treasury_ata: self.treasury_ata,
                owner_ata: ata,
                owner: kp.pubkey(),
                usdc_mint: self.mint,
                token_program: spl_token::ID,
            }
            .to_account_metas(None),
        );
        let server = self.server.insecure_clone();
        send(&mut self.svm, ix, &server, &[&server, &kp]).expect("deposit");
    }

    pub fn new_recipient(&mut self) -> (Keypair, Pubkey) {
        let kp = Keypair::new();
        self.svm.airdrop(&kp.pubkey(), 1_000_000_000).unwrap();
        let ata = CreateAssociatedTokenAccount::new(&mut self.svm, &self.server, &self.mint)
            .owner(&kp.pubkey())
            .send()
            .expect("create recipient ata");
        (kp, ata)
    }
}
