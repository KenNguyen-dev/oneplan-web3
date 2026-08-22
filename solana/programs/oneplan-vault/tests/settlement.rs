mod common;

use {
    anchor_lang::{
        prelude::Pubkey,
        solana_program::instruction::{AccountMeta, Instruction},
        InstructionData, ToAccountMetas,
    },
    common::{after_fee, assert_vault_error, fetch, send, token_balance, usdc, Ctx},
    litesvm_token::spl_token,
    oneplan_vault::{
        error::VaultError,
        state::{Payout, TripVault, VaultStatus},
    },
    solana_signer::Signer,
};

fn close_vault_ix(ctx: &Ctx) -> Instruction {
    Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::CloseVault {}.data(),
        oneplan_vault::accounts::CloseVault {
            vault: ctx.vault,
            vault_ata: ctx.vault_ata,
            server: ctx.server.pubkey(),
            token_program: spl_token::ID,
        }
        .to_account_metas(None),
    )
}

fn execute_settlement_ix(ctx: &Ctx, payouts: Vec<Payout>, recipient_atas: &[Pubkey]) -> Instruction {
    let mut metas = oneplan_vault::accounts::ExecuteSettlement {
        vault: ctx.vault,
        vault_ata: ctx.vault_ata,
        server: ctx.server.pubkey(),
        usdc_mint: ctx.mint,
        token_program: spl_token::ID,
    }
    .to_account_metas(None);
    for ata in recipient_atas {
        metas.push(AccountMeta::new(*ata, false));
    }
    Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::ExecuteSettlement { payouts }.data(),
        metas,
    )
}

#[test]
fn server_execute_settlement_distributes_and_closes() {
    let mut ctx = Ctx::setup(4020, usdc(500), usdc(10000), 2, usdc(1000));
    ctx.deposit(0, usdc(400));
    ctx.deposit(1, usdc(400));

    let alice_net = after_fee(usdc(400));
    let bob_net = after_fee(usdc(400));
    let total = alice_net + bob_net;
    let alice_payout = alice_net + usdc(100);
    let bob_payout = total - alice_payout;

    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.pubkey();
    let bob = ctx.members[1].kp.pubkey();
    let alice_ata = ctx.members[0].ata;
    let bob_ata = ctx.members[1].ata;

    let payouts = vec![
        Payout {
            member: alice,
            amount: alice_payout,
        },
        Payout {
            member: bob,
            amount: bob_payout,
        },
    ];
    let ix = execute_settlement_ix(&ctx, payouts, &[alice_ata, bob_ata]);
    send(&mut ctx.svm, ix, &server, &[&server]).expect("execute_settlement");

    assert_eq!(
        token_balance(&ctx.svm, &alice_ata),
        usdc(1000) - usdc(400) + alice_payout
    );
    assert_eq!(
        token_balance(&ctx.svm, &bob_ata),
        usdc(1000) - usdc(400) + bob_payout
    );
    assert_eq!(token_balance(&ctx.svm, &ctx.vault_ata), 0);

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(vault.status, VaultStatus::Closed);
    assert!(!vault.has_settlement);

    let server_before = ctx
        .svm
        .get_account(&server.pubkey())
        .expect("server")
        .lamports;
    let ix = close_vault_ix(&ctx);
    send(&mut ctx.svm, ix, &server, &[&server]).expect("close_vault");

    assert!(ctx.svm.get_account(&ctx.vault).is_none());
    assert!(ctx.svm.get_account(&ctx.vault_ata).is_none());
    let server_after = ctx
        .svm
        .get_account(&server.pubkey())
        .expect("server")
        .lamports;
    assert!(server_after > server_before);
}

#[test]
fn execute_settlement_rejects_payouts_above_the_balance() {
    let mut ctx = Ctx::setup(4002, usdc(500), usdc(10000), 1, usdc(1000));
    ctx.deposit(0, usdc(100));

    let server = ctx.server.insecure_clone();
    let alice_pubkey = ctx.members[0].kp.pubkey();
    let alice_ata = ctx.members[0].ata;

    let payouts = vec![Payout {
        member: alice_pubkey,
        amount: usdc(500),
    }];
    let ix = execute_settlement_ix(&ctx, payouts, &[alice_ata]);
    let res = send(&mut ctx.svm, ix, &server, &[&server]);

    assert_vault_error(res, VaultError::PayoutsExceedBalance);
}

#[test]
fn execute_settlement_rejects_non_server_signer() {
    let mut ctx = Ctx::setup(4003, usdc(500), usdc(10000), 1, usdc(1000));
    ctx.deposit(0, usdc(100));

    let alice = ctx.members[0].kp.insecure_clone();
    let alice_ata = ctx.members[0].ata;
    let net = after_fee(usdc(100));

    let payouts = vec![Payout {
        member: alice.pubkey(),
        amount: net,
    }];
    // Build the ix with Alice in the `server` slot — has_one = server must refuse.
    let mut metas = oneplan_vault::accounts::ExecuteSettlement {
        vault: ctx.vault,
        vault_ata: ctx.vault_ata,
        server: alice.pubkey(),
        usdc_mint: ctx.mint,
        token_program: spl_token::ID,
    }
    .to_account_metas(None);
    metas.push(AccountMeta::new(alice_ata, false));
    let ix = Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::ExecuteSettlement { payouts }.data(),
        metas,
    );
    let res = send(&mut ctx.svm, ix, &alice, &[&alice]);
    assert!(res.is_err(), "non-server signer must be rejected");
}

fn payout_leave_ix(ctx: &Ctx, member: Pubkey, member_ata: Pubkey, amount: u64) -> Instruction {
    Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::PayoutLeave { amount }.data(),
        oneplan_vault::accounts::PayoutLeave {
            vault: ctx.vault,
            vault_ata: ctx.vault_ata,
            member,
            member_ata,
            server: ctx.server.pubkey(),
            usdc_mint: ctx.mint,
            token_program: spl_token::ID,
        }
        .to_account_metas(None),
    )
}

#[test]
fn payout_leave_pays_one_member_and_keeps_vault_active() {
    let mut ctx = Ctx::setup(4100, usdc(500), usdc(10000), 2, usdc(1000));
    ctx.deposit(0, usdc(400));
    ctx.deposit(1, usdc(200));

    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.pubkey();
    let alice_ata = ctx.members[0].ata;
    let payout = after_fee(usdc(400));
    let vault_before = token_balance(&ctx.svm, &ctx.vault_ata);

    let ix = payout_leave_ix(&ctx, alice, alice_ata, payout);
    send(&mut ctx.svm, ix, &server, &[&server]).expect("payout_leave");

    assert_eq!(
        token_balance(&ctx.svm, &alice_ata),
        usdc(1000) - usdc(400) + payout
    );
    assert_eq!(
        token_balance(&ctx.svm, &ctx.vault_ata),
        vault_before - payout
    );

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(vault.status, VaultStatus::Active);
    assert_eq!(vault.member_count, 1);
    let alice_rec = vault
        .members
        .iter()
        .find(|m| m.owner == alice)
        .expect("alice");
    assert!(!alice_rec.active);
    assert_eq!(alice_rec.refunded, payout);
}

#[test]
fn payout_leave_rejects_amount_above_balance() {
    let mut ctx = Ctx::setup(4101, usdc(500), usdc(10000), 1, usdc(1000));
    ctx.deposit(0, usdc(50));

    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.pubkey();
    let alice_ata = ctx.members[0].ata;
    let ix = payout_leave_ix(&ctx, alice, alice_ata, after_fee(usdc(50)) + 1);
    assert_vault_error(
        send(&mut ctx.svm, ix, &server, &[&server]),
        VaultError::PayoutsExceedBalance,
    );
}
