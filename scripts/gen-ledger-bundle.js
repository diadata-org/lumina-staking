#!/usr/bin/env node
/**
 * gen-ledger-bundle.js — sign a reward bundle with a Ledger device.
 * Writes/extends ledger-bundle-<chainId>.json; verifies each signature on-device.
 * See reward-cron.js for broadcasting.
 *
 * Testnet (default):
 *   node gen-ledger-bundle.js --days 3 --amount 0.01
 * Mainnet (30 days of 548 DIA):
 *   node gen-ledger-bundle.js --network mainnet --days 30 --amount 548
 * Then broadcast daily:
 *   RPC_URL=https://rpc-dia-lasernet-mainnet-n208gs8dc3.t.conduit.xyz \
 *   STAKING=0x677Cf1299c367F6cf6F3E1669aCC18Fd059a5919 \
 *   node reward-cron.js ledger-bundle-1050.json
 *
 * Flags: --network testnet|mainnet · --days N (1-61) · --amount DIA ·
 *   --start-nonce N · --gas-price GWEI · --path "44'/60'/0'/0/0" ·
 *   --no-approve (reuse existing allowance) · --plan-only (status + plan, no device)
 */
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const a = process.argv.slice(2);
const flag = (name, dflt) => {
  const i = a.indexOf(name);
  return i >= 0 && a[i + 1] !== undefined ? a[i + 1] : dflt;
};
const has = (name) => a.includes(name);

const NETWORKS = {
  mainnet: {
    chainId: 1050,
    rpc: "https://rpc-dia-lasernet-mainnet-n208gs8dc3.t.conduit.xyz",
    staking: "0x677Cf1299c367F6cf6F3E1669aCC18Fd059a5919",
    token: "0x9F5dA8630d47178baB71F5923644A28B15cBdCa7",
  },
  testnet: {
    chainId: 10050,
    rpc: "https://testnet-rpc.diadata.org",
    staking: "0x2F521eE9E4D816Ac90BC525036a2d86cc738C0ba",
    token: "0x0F9dceB50A0627bB7627942d00D1757CB3682C51",
  },
};

const netName = flag("--network", "testnet");
const NET = NETWORKS[netName];
if (!NET) { console.error(`--network must be testnet|mainnet (got ${netName})`); process.exit(1); }
const OUTPUT = flag("--output", path.resolve(process.cwd(), `ledger-bundle-${NET.chainId}.json`));

const DAYS = parseInt(flag("--days", "3"), 10);
const AMOUNT_DIA = flag("--amount", "0.01");
const START_NONCE = flag("--start-nonce", null);
const GAS_PRICE_GWEI = flag("--gas-price", null);
const PATH = flag("--path", "44'/60'/0'/0/0");
const PLAN_ONLY = has("--plan-only");
const INCL_APPROVE = !has("--no-approve");

if (!(DAYS >= 1 && DAYS <= 61)) { console.error("--days must be 1..61"); process.exit(1); }

const SEL_APPROVE = ethers.id("approve(address,uint256)").slice(0, 10);
const SEL_ADD = ethers.id("addRewardToPool(uint256)").slice(0, 10);
const pad32 = (h) => h.replace(/^0x/, "").padStart(64, "0");
const fmt = (wei) => ethers.formatEther(wei);

async function main() {
  const amountWei = ethers.parseUnits(AMOUNT_DIA, 18);
  const provider = new ethers.JsonRpcProvider(NET.rpc, NET.chainId, { staticNetwork: true });

  // existing bundle: reuse if same chain+owner, continue from its last nonce
  let existing = null;
  try { existing = JSON.parse(fs.readFileSync(OUTPUT, "utf8")); } catch {}
  if (existing) {
    if (existing.chainId !== NET.chainId)
      { console.error(`existing bundle ${OUTPUT} is chain ${existing.chainId}, expected ${NET.chainId} — use --output`); process.exit(1); }
    if (!Array.isArray(existing.txs) || !existing.txs.length)
      { console.error(`existing bundle ${OUTPUT} has no txs — delete it or use --output`); process.exit(1); }
  }

  const gasPrice = GAS_PRICE_GWEI
    ? ethers.parseUnits(GAS_PRICE_GWEI, "gwei")
    : BigInt(await provider.send("eth_gasPrice", []));
  const signer = await signerAddress();
  if (existing && existing.owner !== signer.toLowerCase())
    { console.error(`existing bundle owner ${existing.owner} != signer ${signer} — use --output for a new file`); process.exit(1); }

  const chainNonce = parseInt(await provider.send("eth_getTransactionCount", [signer, "pending"]), 16);
  const startNonce = START_NONCE !== null
    ? parseInt(START_NONCE, 10)
    : existing
      ? existing.txs[existing.txs.length - 1].nonce + 1
      : chainNonce;

  const total = amountWei * BigInt(DAYS);
  const plan = [];
  let n = startNonce;
  if (INCL_APPROVE) {
    const data = SEL_APPROVE + pad32(NET.staking.toLowerCase()) + pad32(total.toString(16));
    plan.push({ nonce: n++, kind: "approve", to: NET.token, data, gasLimit: 100000n, amountWei: total.toString(), label: `approve ${fmt(total)} -> staking` });
  }
  for (let i = 0; i < DAYS; i++) {
    const data = SEL_ADD + pad32(amountWei.toString(16));
    plan.push({ nonce: n++, kind: "reward", to: NET.staking, data, gasLimit: 200000n, amountWei: amountWei.toString(), label: `day ${i + 1}: addRewardToPool ${fmt(amountWei)}` });
  }

  // chain status for the header
  const sel = (sig) => ethers.id(sig).slice(0, 10);
  const REWARD_ADDED_TOPIC = ethers.id("RewardAdded(uint256,address)");
  const allowanceData = sel("allowance(address,address)") + pad32(signer.slice(2)) + pad32(NET.staking.slice(2));
  const balanceData = sel("balanceOf(address)") + pad32(signer.slice(2));

  const [allowance, balance] = await Promise.all([
    provider.send("eth_call", [{ to: NET.token, data: allowanceData }, "latest"]).then((r) => BigInt(r === "0x" ? 0 : r)),
    provider.send("eth_call", [{ to: NET.token, data: balanceData }, "latest"]).then((r) => BigInt(r === "0x" ? 0 : r)),
  ]);

  // last 5 RewardAdded events
  const lastRewards = [];
  try {
    let end = parseInt(await provider.send("eth_blockNumber", []), 16);
    const CHUNK = netName === "testnet" ? 100_000 : 500_000;
    for (let attempt = 0; attempt < 8 && lastRewards.length < 5 && end >= 0; attempt++) {
      const from = Math.max(0, end - CHUNK + 1);
      let logs;
      try {
        logs = await provider.send("eth_getLogs", [{
          address: NET.staking, topics: [REWARD_ADDED_TOPIC],
          fromBlock: "0x" + from.toString(16), toBlock: "0x" + end.toString(16),
        }]);
      } catch (e) {
        end = from + Math.floor((end - from) / 2);
        continue;
      }
      for (const l of logs) lastRewards.push({
        block: parseInt(l.blockNumber, 16),
        hash: l.transactionHash,
        amount: BigInt("0x" + l.data.slice(2, 66)),
        sender: "0x" + l.data.slice(90),
      });
      if (lastRewards.length >= 5) break;
      if (from === 0) break;
      end = from - 1;
    }
    const blocks = [...new Set(lastRewards.map((r) => r.block))];
    for (const b of blocks) {
      const blk = await provider.send("eth_getBlockByNumber", ["0x" + b.toString(16), false]);
      const ts = Number(BigInt(blk.timestamp));
      lastRewards.filter((r) => r.block === b).forEach((r) => (r.when = new Date(ts * 1000).toISOString().slice(0, 16).replace("T", " ")));
    }
    lastRewards.sort((a, b) => b.block - a.block);
    lastRewards.length = Math.min(lastRewards.length, 5);
  } catch (e) {
    console.log(`(last-txs lookup failed: ${e.message.slice(0, 60)})`);
  }

  console.log(`network     : ${netName} (chain ${NET.chainId})`);
  console.log(`rpc         : ${NET.rpc}`);
  console.log(`signer      : ${PLAN_ONLY ? `${signer} (plan-only, no device)` : "(from Ledger)"}`);
  if (existing) console.log(`existing    : ${OUTPUT} holds ${existing.txs.length} txs (last nonce ${existing.txs[existing.txs.length - 1].nonce}) — appending`);
  console.log(`allowance   : ${fmt(allowance)} -> staking (covers ${Number(allowance / amountWei || 0n)} days @ ${AMOUNT_DIA})`);
  console.log(`balance     : ${fmt(balance)} ${netName === "testnet" ? "WDIA" : "DIA"}`);
  console.log(`start nonce : ${startNonce}`);
  console.log(`gas price   : ${ethers.formatUnits(gasPrice, "gwei")} gwei`);
  console.log(`plan        : ${plan.length} tx(s)`);
  plan.forEach((p) => console.log(`  nonce ${p.nonce}  ${p.kind.padEnd(7)} ${p.label}`));
  console.log(`last 5 rewards:`);
  if (lastRewards.length) lastRewards.forEach((r) =>
    console.log(`  ${r.when} UTC  ${fmt(r.amount).padStart(10)}  ${r.hash.slice(0, 18)}…  by ${r.sender.slice(0, 10)}…`));
  else console.log("  (none found)");

  if (PLAN_ONLY) { console.log("\n(plan-only: nothing signed)"); return; }

  // ---- Ledger signing ----
  const { default: TransportNodeHid } = require("@ledgerhq/hw-transport-node-hid");
  const { default: Eth, ledgerService } = require("@ledgerhq/hw-app-eth");

  console.log("\nconnecting Ledger (unlock it, open the Ethereum app)…");
  const transport = await TransportNodeHid.open("");
  const eth = new Eth(transport);
  try {
    const { address } = await eth.getAddress(PATH);
    console.log(`ledger addr : ${address}`);

    const txs = [];
    for (const p of plan) {
      const tx = ethers.Transaction.from({
        to: p.to, nonce: p.nonce, gasLimit: p.gasLimit, gasPrice,
        data: p.data, chainId: NET.chainId, type: 0,
      });
      console.log(`\nsign nonce ${p.nonce} (${p.kind}) — CONFIRM ON DEVICE: ${p.label}`);
      const rawHex = tx.unsignedSerialized.slice(2);
      // resolution config required by current hw-app-eth; falls back to blind signing
      let resolution = {};
      try {
        resolution = await ledgerService.resolveTransaction(
          rawHex,
          { domains: [], externalPlugins: [], nft: false },
          {}
        );
      } catch (e) {
        console.log(`  (contract resolution unavailable — blind signing; enable 'Contract data' on device)`);
      }
      const sig = await eth.signTransaction(PATH, rawHex, resolution);

      // normalize v: device returns bare hex, usually EIP-155 already
      let v = BigInt("0x" + sig.v.replace(/^0x/, ""));
      if (v <= 1n) v = BigInt(NET.chainId) * 2n + 35n + v;
      else if (v === 27n || v === 28n) v = v - 27n + BigInt(NET.chainId) * 2n + 35n;

      const signed = ethers.Transaction.from({
        ...tx.toJSON(), type: 0,
        signature: { r: "0x" + sig.r, s: "0x" + sig.s, v },
      });
      if (!signed.from || signed.from.toLowerCase() !== address.toLowerCase()) {
        throw new Error(`signature at nonce ${p.nonce} recovered to ${signed.from}, expected ${address} — NOT SAVED`);
      }
      txs.push({ nonce: p.nonce, kind: p.kind, amountWei: p.amountWei, hash: ethers.keccak256(signed.serialized), raw: signed.serialized });
      console.log(`  ok ${txs[txs.length - 1].hash}`);
    }

    // lastNonce = fresh on-chain pending nonce at write time
    const chainNonceNow = parseInt(await provider.send("eth_getTransactionCount", [address, "pending"]), 16);
    const bundle = {
      owner: address.toLowerCase(),
      chainId: NET.chainId,
      dailyAmountWei: amountWei.toString(),
      dailyAmount: AMOUNT_DIA,
      network: netName,
      lastNonce: chainNonceNow,
      lastTxHash: txs[txs.length - 1].hash,
      txs: [...(existing ? existing.txs : []), ...txs],
    };
    fs.writeFileSync(OUTPUT, JSON.stringify(bundle, null, 2));
    console.log(`\nbundle written: ${OUTPUT} (${bundle.txs.length} txs total: ${existing ? existing.txs.length + " existing + " : ""}${txs.length} new, owner ${bundle.owner})`);
    console.log(`next: node reward-cron.js ${OUTPUT}`);
  } finally {
    await transport.close();
  }
}

// plan-only signer: from device if present, else OWNER env (or burner default on testnet)
async function signerAddress() {
  if (!PLAN_ONLY) {
    const { default: TransportNodeHid } = require("@ledgerhq/hw-transport-node-hid");
    const { default: Eth } = require("@ledgerhq/hw-app-eth");
    const t = await TransportNodeHid.open("");
    try { return (await new Eth(t).getAddress(PATH)).address; }
    finally { await t.close(); }
  }
  return process.env.OWNER || "0x73d597d9b948742a0a0F1dAb2dB13f683F25cF65";
}

main().catch((e) => { console.error("FAILED:", e.message || e); process.exit(1); });
