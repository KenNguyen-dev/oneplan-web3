mod common;

use {
    anchor_lang::{
        prelude::Pubkey, solana_program::instruction::Instruction, InstructionData, ToAccountMetas,
    },
    common::{assert_vault_error, fetch, send, token_balance, usdc, warp_seconds, Ctx},
    litesvm_token::spl_token,
    oneplan_vault::{error::VaultError, state::TripVault},
    solana_signer::Signer,
};

fn spend_ix(ctx: &Ctx, member_index: usize, recipient_ata: &Pubkey, amount: u64) -> Instruction {
    Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::Spend { amount }.data(),
        oneplan_vault::accounts::Spend {
            vault: ctx.vault,
            vault_ata: ctx.vault_ata,
            signer: ctx.members[member_index].kp.pubkey(),
            recipient_ata: *recipient_ata,
            usdc_mint: ctx.mint,
            token_program: spl_token::ID,
        }
        .to_account_metas(None),
    )
}

#[test]
fn spend_transfers_when_within_the_threshold() {
    let mut ctx = Ctx::setup(2001, usdc(500), usdc(2000), 2, usdc(1000));
    ctx.deposit(0, usdc(800));
    let (_, recipient_ata) = ctx.new_recipient();
    let net = common::after_fee(usdc(800));

    let ix = spend_ix(&ctx, 0, &recipient_ata, usdc(120));
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("spend");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(vault.total_spent, usdc(120));
    assert_eq!(vault.spent_today, usdc(120));
    assert_eq!(token_balance(&ctx.svm, &recipient_ata), usdc(120));
    assert_eq!(token_balance(&ctx.svm, &ctx.vault_ata), net - usdc(120));
}

#[test]
fn spend_rejects_amounts_above_the_threshold() {
    let mut ctx = Ctx::setup(2002, usdc(500), usdc(2000), 1, usdc(1000));
    ctx.deposit(0, usdc(900));
    let (_, recipient_ata) = ctx.new_recipient();

    let ix = spend_ix(&ctx, 0, &recipient_ata, usdc(600));
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    let res = send(&mut ctx.svm, ix, &server, &[&server, &alice]);

    assert_vault_error(res, VaultError::AboveThreshold);
}

#[test]
fn spend_rejects_breaching_the_daily_ceiling() {
    let mut ctx = Ctx::setup(2003, usdc(500), usdc(600), 1, usdc(2000));
    ctx.deposit(0, usdc(1500));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();

    let ix = spend_ix(&ctx, 0, &recipient_ata, usdc(400));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("first spend");

    let ix = spend_ix(&ctx, 0, &recipient_ata, usdc(400));
    let res = send(&mut ctx.svm, ix, &server, &[&server, &alice]);
    assert_vault_error(res, VaultError::DailyLimitExceeded);
}

#[test]
fn the_daily_window_resets_after_24_hours() {
    let mut ctx = Ctx::setup(2005, usdc(500), usdc(600), 1, usdc(2000));
    ctx.deposit(0, usdc(1500));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();

    let ix = spend_ix(&ctx, 0, &recipient_ata, usdc(400));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("first spend");

    warp_seconds(&mut ctx.svm, 86_401);

    let ix = spend_ix(&ctx, 0, &recipient_ata, usdc(400));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("spend after the window reset");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(vault.total_spent, usdc(800));
    assert_eq!(vault.spent_today, usdc(400));
}

#[test]
fn revert_spend_returns_funds_and_decrements_total_spent() {
    let mut ctx = Ctx::setup(2004, usdc(500), usdc(2000), 1, usdc(1000));
    ctx.deposit(0, usdc(700));
    let net = common::after_fee(usdc(700));
    let (receiver, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();

    let ix = spend_ix(&ctx, 0, &recipient_ata, usdc(200));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("spend");

    let ix = Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::RevertSpend { amount: usdc(200) }.data(),
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
    send(&mut ctx.svm, ix, &server, &[&server, &receiver]).expect("revert_spend");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(vault.total_spent, 0);
    assert_eq!(token_balance(&ctx.svm, &ctx.vault_ata), net);
    assert_eq!(token_balance(&ctx.svm, &recipient_ata), 0);
}
