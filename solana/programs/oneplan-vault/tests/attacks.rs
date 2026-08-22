mod common;

use {
    anchor_lang::{
        prelude::Pubkey, solana_program::instruction::Instruction, InstructionData, ToAccountMetas,
    },
    common::{after_fee, assert_vault_error, send, token_balance, usdc, warp_seconds, Ctx},
    litesvm_token::spl_token,
    oneplan_vault::error::VaultError,
    solana_keypair::Keypair,
    solana_signer::Signer,
};

fn spend_ix(ctx: &Ctx, signer: Pubkey, recipient_ata: &Pubkey, amount: u64) -> Instruction {
    Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::Spend { amount }.data(),
        oneplan_vault::accounts::Spend {
            vault: ctx.vault,
            vault_ata: ctx.vault_ata,
            signer,
            recipient_ata: *recipient_ata,
            usdc_mint: ctx.mint,
            token_program: spl_token::ID,
        }
        .to_account_metas(None),
    )
}

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

#[test]
fn a_non_member_cannot_spend() {
    let mut ctx = Ctx::setup(5001, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let net = after_fee(usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();

    let outsider = Keypair::new();
    ctx.svm.airdrop(&outsider.pubkey(), 1_000_000_000).unwrap();

    let ix = spend_ix(&ctx, outsider.pubkey(), &recipient_ata, usdc(100));
    let server = ctx.server.insecure_clone();
    let res = send(&mut ctx.svm, ix, &server, &[&server, &outsider]);

    assert_vault_error(res, VaultError::MemberNotFound);
    assert_eq!(token_balance(&ctx.svm, &recipient_ata), 0);
    assert_eq!(token_balance(&ctx.svm, &ctx.vault_ata), net);
}

#[test]
fn a_deactivated_member_cannot_spend() {
    let mut ctx = Ctx::setup(5002, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let authority = ctx.authority.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();

    let ix = Instruction::new_with_bytes(
        ctx.program_id,
        &oneplan_vault::instruction::DeactivateMember {}.data(),
        oneplan_vault::accounts::DeactivateMember {
            vault: ctx.vault,
            owner: alice.pubkey(),
            authority: authority.pubkey(),
        }
        .to_account_metas(None),
    );
    send(&mut ctx.svm, ix, &server, &[&server, &authority]).expect("deactivate_member");

    let ix = spend_ix(&ctx, alice.pubkey(), &recipient_ata, usdc(100));
    let res = send(&mut ctx.svm, ix, &server, &[&server, &alice]);

    assert_vault_error(res, VaultError::MemberNotActive);
}

#[test]
fn the_proposer_cannot_approve_their_own_proposal() {
    let mut ctx = Ctx::setup(5003, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    let ix = approve_ix(&ctx, 0, &recipient_ata);
    let res = send(&mut ctx.svm, ix, &server, &[&server, &alice]);

    assert_vault_error(res, VaultError::DuplicateApproval);
    assert_eq!(token_balance(&ctx.svm, &recipient_ata), 0);
}

#[test]
fn an_executed_spend_slot_cannot_be_approved_again() {
    let mut ctx = Ctx::setup(5004, usdc(500), usdc(10000), 3, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    let bob = ctx.members[1].kp.insecure_clone();
    let carol = ctx.members[2].kp.insecure_clone();

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    let ix = approve_ix(&ctx, 1, &recipient_ata);
    send(&mut ctx.svm, ix, &server, &[&server, &bob]).expect("second approval executes");

    let ix = approve_ix(&ctx, 2, &recipient_ata);
    let res = send(&mut ctx.svm, ix, &server, &[&server, &carol]);

    assert_vault_error(res, VaultError::NoActiveSpend);
    assert_eq!(token_balance(&ctx.svm, &recipient_ata), usdc(900));
}

#[test]
fn spending_from_an_empty_vault_is_rejected() {
    let mut ctx = Ctx::setup(5005, usdc(500), usdc(10000), 1, usdc(10));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();

    let ix = spend_ix(&ctx, alice.pubkey(), &recipient_ata, usdc(100));
    let res = send(&mut ctx.svm, ix, &server, &[&server, &alice]);

    assert_vault_error(res, VaultError::InsufficientFunds);
}

#[test]
fn an_expired_proposal_cannot_be_approved() {
    let mut ctx = Ctx::setup(5006, usdc(500), usdc(10000), 2, usdc(3000));
    ctx.deposit(0, usdc(2000));
    let net = after_fee(usdc(2000));
    let (_, recipient_ata) = ctx.new_recipient();
    let server = ctx.server.insecure_clone();
    let alice = ctx.members[0].kp.insecure_clone();
    let bob = ctx.members[1].kp.insecure_clone();

    let ix = propose_ix(&ctx, 0, &recipient_ata, usdc(900));
    send(&mut ctx.svm, ix, &server, &[&server, &alice]).expect("propose_spend");

    warp_seconds(&mut ctx.svm, 86_401);

    let ix = approve_ix(&ctx, 1, &recipient_ata);
    let res = send(&mut ctx.svm, ix, &server, &[&server, &bob]);

    assert_vault_error(res, VaultError::ProposalExpired);
    assert_eq!(token_balance(&ctx.svm, &ctx.vault_ata), net);
}
