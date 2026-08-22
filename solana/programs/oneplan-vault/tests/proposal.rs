mod common;

use {
    anchor_lang::{
        prelude::Pubkey, solana_program::instruction::Instruction, InstructionData, ToAccountMetas,
    },
    common::{assert_vault_error, fetch, send, token_balance, usdc, Ctx},
    litesvm_token::spl_token,
    oneplan_vault::{error::VaultError, state::TripVault},
    solana_signer::Signer,
};

fn propose_ix(ctx: &Ctx, member_index: usize, recipient_ata: &Pubkey, amount: u64) -> Instruction {
    Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::ProposeSpend { amount }.data(),
        oneplan_vault::accounts::ProposeSpend {
            vault: ctx.vault,
            signer: ctx.members[member_index].kp.pubkey(),
            recipient_ata: *recipient_ata,
        }
        .to_account_metas(None),
    )
}

fn approve_ix(ctx: &Ctx, member_index: usize, recipient_ata: &Pubkey) -> Instruction {
    Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::ApproveSpend {}.data(),
        oneplan_vault::accounts::ApproveSpend {
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

fn cancel_ix(ctx: &Ctx, member_index: usize) -> Instruction {
    Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::CancelSpend {}.data(),
        oneplan_vault::accounts::CancelSpend {
            vault: ctx.vault,
            signer: ctx.members[member_index].kp.pubkey(),
        }
        .to_account_metas(None),
    )
}

fn set_role_ix(ctx: &Ctx, member_index: usize, role: u8) -> Instruction {
    Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::SetMemberRole { role }.data(),
        oneplan_vault::accounts::SetMemberRole {
            vault: ctx.vault,
            owner: ctx.members[member_index].kp.pubkey(),
            server: ctx.server.pubkey(),
        }
        .to_account_metas(None),
    )
}

#[test]
fn a_proposal_executes_only_on_the_second_approval() {
    let mut ctx = Ctx::setup(3001, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    let bob = ctx.members[1].kp.insecure_clone();

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert!(vault.has_active_spend);
    assert_eq!(vault.active_spend.approvals.len(), 1);
    assert_eq!(token_balance(&ctx.svm, &recipient_ata), 0);

    let ix = approve_ix(&ctx, 1, &recipient_ata);
    send(&mut ctx.svm, ix, &server, &[&server, &bob]).expect("approve_spend");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert!(!vault.has_active_spend);
    assert_eq!(token_balance(&ctx.svm, &recipient_ata), usdc(900));
    assert_eq!(vault.total_spent, usdc(900));
    assert_eq!(vault.spent_today, 0);
}

#[test]
fn propose_rejects_amounts_within_the_threshold() {
    let mut ctx = Ctx::setup(3002, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(100));
    let res = send(&mut ctx.svm, ix, &server, &[&server, &alice]);

    assert_vault_error(res, VaultError::BelowThreshold);
}

#[test]
fn proposer_can_cancel_active_spend() {
    let mut ctx = Ctx::setup(3003, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    let ix = cancel_ix(&ctx, 0);
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("cancel_spend");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert!(!vault.has_active_spend);
}

#[test]
fn other_member_cannot_occupy_spend_slot() {
    let mut ctx = Ctx::setup(3004, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    let bob = ctx.members[1].kp.insecure_clone();

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    let ix = propose_ix(&ctx, 1, &recipient_ata, usdc(800));
    assert_vault_error(
        send(&mut ctx.svm, ix, &server, &[&server, &bob]),
        VaultError::SpendSlotOccupied,
    );
}

#[test]
fn host_can_supersede_another_members_spend() {
    let mut ctx = Ctx::setup(3006, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_a) = ctx.new_recipient();
    let (_, recipient_b) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    let bob = ctx.members[1].kp.insecure_clone();

    // Bob is HOST/CO_HOST (approver).
    let ix = set_role_ix(&ctx, 1, 1);
    send(&mut ctx.svm, ix, &server, &[&server]).expect("set_member_role");

    let ix = propose_ix(&ctx, 0, &recipient_a, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    let ix = propose_ix(&ctx, 1, &recipient_b, usdc(700));
    send(&mut ctx.svm, ix, &server, &[&server, &bob]).expect("host supersede");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(vault.active_spend.proposer, bob.pubkey());
    assert_eq!(vault.active_spend.amount, usdc(700));
    assert_eq!(vault.active_spend.recipient, recipient_b);
}

#[test]
fn same_proposer_can_supersede() {
    let mut ctx = Ctx::setup(3005, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_a) = ctx.new_recipient();
    let (_, recipient_b) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();

    let ix = propose_ix(&ctx, 0, &recipient_a, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    let ix = propose_ix(&ctx, 0, &recipient_b, usdc(700));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("supersede");

    let vault: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(vault.active_spend.amount, usdc(700));
    assert_eq!(vault.active_spend.recipient, recipient_b);
}

#[test]
fn one_approver_leaves_approval_open_to_everyone() {
    let mut ctx = Ctx::setup(3010, usdc(500), usdc(10000), 3, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    let carol = ctx.members[2].kp.insecure_clone();

    let ix = set_role_ix(&ctx, 0, 1);
    send(&mut ctx.svm, ix, &server, &[&server]).expect("set_member_role");
    let v: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(v.approver_count, 1);

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    let ix = approve_ix(&ctx, 2, &recipient_ata);
    send(&mut ctx.svm, ix, &server, &[&server, &carol]).expect("approve_spend");

    assert_eq!(token_balance(&ctx.svm, &recipient_ata), usdc(900));
}

#[test]
fn two_approvers_shut_everyone_else_out() {
    let mut ctx = Ctx::setup(3011, usdc(500), usdc(10000), 3, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    let bob = ctx.members[1].kp.insecure_clone();
    let carol = ctx.members[2].kp.insecure_clone();

    for index in [0, 1] {
        let ix = set_role_ix(&ctx, index, 1);
        send(&mut ctx.svm, ix, &server, &[&server]).expect("set_member_role");
    }
    let v: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(v.approver_count, 2);

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    let ix = approve_ix(&ctx, 2, &recipient_ata);
    assert_vault_error(
        send(&mut ctx.svm, ix, &server, &[&server, &carol]),
        VaultError::NotAnApprover,
    );
    assert_eq!(token_balance(&ctx.svm, &recipient_ata), 0);

    let ix = approve_ix(&ctx, 1, &recipient_ata);
    send(&mut ctx.svm, ix, &server, &[&server, &bob]).expect("approve_spend");
    assert_eq!(token_balance(&ctx.svm, &recipient_ata), usdc(900));
}

#[test]
fn demoting_an_approver_reopens_approval() {
    let mut ctx = Ctx::setup(3012, usdc(500), usdc(10000), 3, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    let carol = ctx.members[2].kp.insecure_clone();

    for index in [0, 1] {
        let ix = set_role_ix(&ctx, index, 1);
        send(&mut ctx.svm, ix, &server, &[&server]).expect("set_member_role");
    }
    let ix = set_role_ix(&ctx, 1, 0);
    send(&mut ctx.svm, ix, &server, &[&server]).expect("set_member_role");
    let v: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(v.approver_count, 1);

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");
    let ix = approve_ix(&ctx, 2, &recipient_ata);
    send(&mut ctx.svm, ix, &server, &[&server, &carol]).expect("approve_spend");

    assert_eq!(token_balance(&ctx.svm, &recipient_ata), usdc(900));
}

#[test]
fn repeating_a_role_does_not_double_count() {
    let mut ctx = Ctx::setup(3013, usdc(500), usdc(10000), 2, usdc(3000));
    let server = ctx.server.insecure_clone();

    for _ in 0..3 {
        let ix = set_role_ix(&ctx, 0, 1);
        send(&mut ctx.svm, ix, &server, &[&server]).expect("set_member_role");
    }
    let v: TripVault = fetch(&ctx.svm, &ctx.vault);
    assert_eq!(v.approver_count, 1);
}

#[test]
fn the_trip_authority_cannot_set_roles() {
    let mut ctx = Ctx::setup(3014, usdc(500), usdc(10000), 2, usdc(3000));
    let server = ctx.server.insecure_clone();
    let authority = ctx.authority.insecure_clone();

    let ix = Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::SetMemberRole { role: 1 }.data(),
        oneplan_vault::accounts::SetMemberRole {
            vault: ctx.vault,
            owner: ctx.members[0].kp.pubkey(),
            server: authority.pubkey(),
        }
        .to_account_metas(None),
    );
    assert!(send(&mut ctx.svm, ix, &server, &[&server, &authority]).is_err());
}
