mod common;

use {
    anchor_lang::{solana_program::instruction::Instruction, InstructionData, ToAccountMetas},
    common::{fetch, send, token_balance, usdc, Ctx},
    litesvm_token::spl_token,
    oneplan_vault::state::TripVault,
    solana_signer::Signer,
};

fn next(seed: &mut u64) -> u64 {
    *seed = seed
        .wrapping_mul(6364136223846793005)
        .wrapping_add(1442695040888963407);
    (*seed >> 33) % 3
}

#[test]
fn the_accounting_invariant_holds_after_every_operation() {
    let mut ctx = Ctx::setup(6001, usdc(500), usdc(1_000_000), 2, usdc(5000));
    let (receiver, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();

    fn check(ctx: &Ctx) {
        let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
        let balance = token_balance(&ctx.svm, &ctx.vault_ata);
        assert_eq!(
            vault.total_deposited - vault.total_spent,
            balance,
            "invariant broken: deposited={} spent={} ata={}",
            vault.total_deposited,
            vault.total_spent,
            balance
        );
    }

    let mut seed: u64 = 42;
    let mut outstanding: u64 = 0;
    let member_count = ctx.members.len();

    for i in 0..30 {
        let member_index = i % member_count;
        match next(&mut seed) {
            0 => {
                ctx.deposit(member_index, usdc(50));
            }
            1 => {
                let kp = ctx.members[member_index].kp.insecure_clone();
                let ix = Instruction::new_with_bytes(
                    ctx.program_id,
                    &oneplan_vault::instruction::Spend { amount: usdc(20) }.data(),
                    oneplan_vault::accounts::Spend {
                        vault: ctx.vault,
                        vault_ata: ctx.vault_ata,
                        signer: kp.pubkey(),
                        recipient_ata,
                        usdc_mint: ctx.mint,
                        token_program: spl_token::ID,
                    }
                    .to_account_metas(None),
                );
                if send(&mut ctx.svm, ix, &server, &[&server, &kp]).is_ok() {
                    outstanding += usdc(20);
                }
            }
            _ => {
                if outstanding >= usdc(10) {
                    let ix = Instruction::new_with_bytes(
                        ctx.program_id,
                        &oneplan_vault::instruction::RevertSpend { amount: usdc(10) }.data(),
                        oneplan_vault::accounts::RevertSpend {
                            vault: ctx.vault,
                            vault_ata: ctx.vault_ata,
                            receiver_ata: recipient_ata,
                            receiver: receiver.pubkey(),
                            server: server.pubkey(),
                            usdc_mint: ctx.mint,
                            token_program: spl_token::ID,
                        }
                        .to_account_metas(None),
                    );
                    send(&mut ctx.svm, ix, &server, &[&server, &receiver])
                        .expect("revert_spend");
                    outstanding -= usdc(10);
                }
            }
        }
        check(&ctx);
    }

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert!(vault.total_deposited > 0, "no deposits were made");
    assert!(vault.total_spent > 0, "no spends were made");
}
