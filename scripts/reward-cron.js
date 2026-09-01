#!/usr/bin/env node
/**
 * reward-cron.js — daily cron for pre-signed reward txs. Zero deps, zero state files.
 * Chain is the only source of truth:
 *   - next tx   = owner's pending nonce
 *   - last day  = newest RewardAdded event by the owner
 * 1 reward/day; missed days are caught up in nonce order.
 * Cron: 0 9 * * * cd <dir> && node reward-cron.js ledger-bundle-10050.json >> reward.log 2>&1
 * Env: RPC_URL, STAKING, DRY_RUN=1. Exit: 0 ok · 1 error · 2 bundle exhausted.
 */
const fs = require("fs");

const RPC = process.env.RPC_URL || "https://testnet-rpc.diadata.org";
const STAKING = process.env.STAKING || "0x2F521eE9E4D816Ac90BC525036a2d86cc738C0ba";
const DRY = process.env.DRY_RUN === "1";
const REWARD_ADDED_TOPIC = "0xfb5edb6eb340a01f6a67189edc978df97841c43752c212fc85995ea230017635";
const CHUNK = parseInt(process.env.LOG_CHUNK || "100000", 10);

const bundleFile = process.argv[2] || "ledger-bundle.json";
const day = () => Math.floor(Date.now() / 86400e3);
const log = (m) => console.log(`${new Date().toISOString()} ${m}`);
const die = (m, code = 1) => { console.error(`${new Date().toISOString()} ERROR: ${m}`); process.exit(code); };

const rpc = (method, params) =>
  fetch(RPC, { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) })
    .then((r) => r.json())
    .then((b) => { if (b.error) throw new Error(`${method}: ${b.error.message}`); return b.result; });

async function waitReceipt(hash, timeoutS = 120) {
  for (let i = 0; i < timeoutS / 3; i++) {
    const rc = await rpc("eth_getTransactionReceipt", [hash]).catch(() => null);
    if (rc) return rc;
    await new Promise((r) => setTimeout(r, 3000));
  }
  return null;
}

async function sendAtNonce(tx) {
  try {
    await rpc("eth_sendRawTransaction", [tx.raw]);
  } catch (e) {
    const m = e.message || "";
    if (/nonce too low/i.test(m)) { log(`  nonce too low — already mined, skipping`); return; }
    if (!/already known|already in/i.test(m)) throw e;
    log(`  already in mempool — waiting for receipt`);
  }
  const rc = await waitReceipt(tx.hash);
  if (!rc) die(`no receipt for ${tx.hash} — rerun after it mines`);
  if (rc.status !== "0x1") die(`tx REVERTED ${tx.hash} — investigate, then rerun`);
}

/** UTC day of the owner's newest RewardAdded, or null if none ever. */
async function lastRewardedDay(owner) {
  let end = parseInt(await rpc("eth_blockNumber", []), 16);
  for (let attempt = 0; attempt < 8 && end >= 0; attempt++) {
    const from = Math.max(0, end - CHUNK + 1);
    let logs;
    try {
      logs = await rpc("eth_getLogs", [{
        address: STAKING, topics: [REWARD_ADDED_TOPIC],
        fromBlock: "0x" + from.toString(16), toBlock: "0x" + end.toString(16),
      }]);
    } catch { end = from + Math.floor((end - from) / 2); continue; }
    for (let i = logs.length - 1; i >= 0; i--) {
      const sender = "0x" + logs[i].data.slice(90).toLowerCase();
      if (sender === owner.toLowerCase()) {
        const blk = await rpc("eth_getBlockByNumber", [logs[i].blockNumber, false]);
        return Math.floor(Number(BigInt(blk.timestamp)) / 86400);
      }
    }
    if (from === 0) return null;
    end = from - 1;
  }
  return null;
}

async function main() {
  const bundle = JSON.parse(fs.readFileSync(bundleFile, "utf8"));
  const byNonce = new Map(bundle.txs.map((t) => [t.nonce, t]));
  const rewards = bundle.txs.filter((t) => t.kind === "reward");
  if (!rewards.length) die("bundle has no reward txs");

  let nonce = parseInt(await rpc("eth_getTransactionCount", [bundle.owner, "pending"]), 16);
  const remainingRewards = () => rewards.filter((t) => t.nonce >= nonce).length;
  const amt = (t) => (t.amountWei ? ` (${Number(t.amountWei) / 1e18} tokens)` : "");

  // drain any approve at the chain's next nonce first (not day-gated)
  while (byNonce.has(nonce) && byNonce.get(nonce).kind === "approve") {
    const ap = byNonce.get(nonce);
    log(`approve at chain nonce ${ap.nonce}${amt(ap)}: ${ap.hash}`);
    if (!DRY) await sendAtNonce(ap);
    nonce++;
  }

  const today = day();
  const lastDay = await lastRewardedDay(bundle.owner);
  let due;
  if (lastDay === null) due = 1;
  else if (today <= lastDay) { log(`last reward landed today (chain) — nothing due`); return; }
  else due = today - lastDay;

  let left = remainingRewards();
  if (left === 0) { log(`bundle exhausted (chain nonce ${nonce} past all rewards) — generate a new bundle`); process.exit(2); }
  const sendCount = Math.min(due, left);
  if (sendCount < due) log(`WARNING: ${due} due but only ${sendCount} left in bundle`);
  log(`chain nonce ${nonce} · last reward day ${lastDay ?? "never"} · today ${today} · due ${due} · sending ${sendCount}`);

  for (let i = 0; i < sendCount; i++) {
    while (byNonce.has(nonce) && byNonce.get(nonce).kind === "approve") { // interleaved approve (append)
      const ap = byNonce.get(nonce);
      log(`[approve] chain nonce ${ap.nonce}: ${ap.hash}`);
      if (!DRY) await sendAtNonce(ap);
      nonce++;
    }
    const tx = byNonce.get(nonce);
    if (!tx) {
      const next = rewards.find((t) => t.nonce > nonce);
      die(`nonce gap: chain expects ${nonce} but next bundle reward is ${next ? next.nonce : "none"} — bundle unusable past this point`);
    }
    log(`[${i + 1}/${sendCount}] reward at chain nonce ${tx.nonce}${amt(tx)}: ${tx.hash}`);
    if (!DRY) await sendAtNonce(tx);
    nonce++;
    log(`  ok — ${remainingRewards()} reward txs remain`);
  }

  left = remainingRewards();
  log(`done. ${left} reward txs remain${left <= 3 ? " — bundle running low!" : ""}`);
}

main().catch((e) => die(e.message));
