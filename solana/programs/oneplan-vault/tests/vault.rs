mod common;

use {
    anchor_lang::{solana_program::instruction::Instruction, InstructionData, ToAccountMetas},
    common::{after_fee, fetch, send, token_balance, usdc, Ctx},
    litesvm_token::spl_token,
    oneplan_vault::state::{TripVault, VaultStatus},
    solana_signer::Signer,
};

#[test]
fn init_vault_stores_the_config() {
    let ctx = Ctx::setup(1001, usdc(500), usdc(2000), 0, 0);
    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);

    assert_eq!(vault.trip_id, 1001);
    assert_eq!(vault.authority, ctx.authority.pubkey());
    assert_eq!(vault.server, ctx.server.pubkey());
    assert_eq!(vault.usdc_mint, ctx.mint);
    assert_eq!(vault.threshold, usdc(500));
    assert_eq!(vault.daily_limit, usdc(2000));
    assert_eq!(vault.total_deposited, 0);
    assert_eq!(vault.total_spent, 0);
    assert_eq!(vault.member_count, 0);
    assert!(vault.members.is_empty());
    assert!(!vault.has_active_spend);
    assert!(!vault.has_settlement);
    assert_eq!(vault.status, VaultStatus::Active);
}

#[test]
fn add_member_needs_only_the_authority() {
    let ctx = Ctx::setup(1002, usdc(500), usdc(2000), 1, usdc(1000));
    let alice = &ctx.members[0];

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(vault.member_count, 1);
    assert_eq!(vault.members.len(), 1);
    assert_eq!(vault.members[0].owner, alice.kp.pubkey());
    assert!(vault.members[0].active);
    assert_eq!(vault.members[0].deposited, 0);
}

#[test]
fn deactivate_member_keeps_the_contribution_record() {
    let mut ctx = Ctx::setup(1003, usdc(500), usdc(2000), 1, usdc(1000));
    let owner = ctx.members[0].kp.pubkey();

    let ix = Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::DeactivateMember {}.data(),
        oneplan_vault::accounts::DeactivateMember {
            vault: ctx.vault,
            owner,
            authority: ctx.authority.pubkey(),
        }
        .to_account_metas(None),
    );
    let authority = ctx.authority.insecure_clone();
    let server = ctx.server.insecure_clone();
    send(&mut ctx.svm, ix, &server, &[&server, &authority]).expect("deactivate_member");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert!(!vault.members[0].active);
    assert_eq!(vault.members[0].deposited, 0);
    assert_eq!(vault.member_count, 0);
}

#[test]
fn deposit_moves_usdc_skims_fee_and_records_net() {
    let mut ctx = Ctx::setup(1004, usdc(500), usdc(2000), 1, usdc(1000));
    let alice_kp = ctx.members[0].kp.insecure_clone();
    let alice_ata = ctx.members[0].ata;
    let amount = usdc(300);
    let net = after_fee(amount);
    let fee = amount - net;

    let ix = Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::Deposit { amount }.data(),
        oneplan_vault::accounts::Deposit {
            vault: ctx.vault,
            vault_ata: ctx.vault_ata,
            treasury_ata: ctx.treasury_ata,
            owner_ata: alice_ata,
            owner: alice_kp.pubkey(),
            usdc_mint: ctx.mint,
            token_program: spl_token::ID,
        }
        .to_account_metas(None),
    );
    let server = ctx.server.insecure_clone();
    send(&mut ctx.svm, ix, &server, &[&server, &alice_kp]).expect("deposit");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);

    assert_eq!(vault.total_deposited, net);
    assert_eq!(vault.members[0].deposited, net);
    assert_eq!(token_balance(&ctx.svm, &ctx.vault_ata), net);
    assert_eq!(token_balance(&ctx.svm, &ctx.treasury_ata), fee);
    assert_eq!(token_balance(&ctx.svm, &alice_ata), usdc(1000) - amount);
}
