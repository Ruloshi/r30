# Rule 30 — Mathematical Foundations & Smart Contract Design

This document explains the mathematics behind the $R30 project, why each cell of the pyramid is treated as an **agent**, and how these ideas are translated into the `Rule30` smart contract (source file `R30_13.sol`).

---

## 1. What is a cellular automaton?

Formally, a one-dimensional cellular automaton is defined by:

- A lattice of cells, each holding a state from a finite alphabet — here, `{0, 1}` (Dead, Alive)
- A **local transition function** `f : {0,1}³ → {0,1}` that computes a cell's next state from the states of itself and its two immediate neighbors
- A global update rule: every cell applies `f` **simultaneously**, producing the next generation from the current one

Despite the extreme simplicity of this definition, iterating `f` can produce behavior ranging from perfect order, to self-similar fractals, to full computational complexity — entirely deterministically, with no randomness anywhere in the rule itself.

Wolfram's 1983 classification groups this range into four qualitative behavior classes:

| Class | Behavior | Example |
|---|---|---|
| I | Converges to a uniform, static state | Rule 0, 8, ... |
| II | Converges to simple, periodic, or nested structures | many rules |
| III | Chaotic, pseudo-random behavior | **Rule 30** |
| IV | Localized structures interacting in complex ways; capable of universal computation | **Rule 110** |

---

## 2. Elementary cellular automata

An **elementary cellular automaton** is exactly the case above: `f` depends on 3 binary inputs (left, center, right), so there are 2³ = 8 possible neighborhoods. A rule assigns one output bit to each of the 8 cases, so there are exactly **2⁸ = 256 possible rules**, each identified by the integer whose binary digits are those 8 outputs, read in a fixed order. This numbering was introduced by Stephen Wolfram and is the standard convention used throughout this document.

### Rule 30

Rule 30 corresponds to `30 = 00011110` in binary:

| Neighborhood (L, C, R) | 111 | 110 | 101 | 100 | 011 | 010 | 001 | 000 |
|---|---|---|---|---|---|---|---|---|
| **f(L,C,R)**            | 0   | 0   | 0   | 1   | 1   | 1   | 1   | 0   |

Equivalently, Rule 30 can be written as the Boolean expression:

```
f(L, C, R) = L XOR (C OR R)
```

Starting from a single live cell and applying this rule repeatedly produces a triangular pattern that is **visibly chaotic** and, as far as is known, unpredictable (§3) — this is the mathematical engine behind the pyramid.

### Rule 90 and Rule 110, for context

The site's Agent Explorer also lets you run two other historically significant rules:

- **Rule 90**: `f(L, C, R) = L XOR R` (the center cell's own state is ignored entirely). Starting from a single seed, this generates the **Sierpiński triangle** — an exactly self-similar fractal with Hausdorff dimension `log(3)/log(2) ≈ 1.585`.
- **Rule 110**: proven by Matthew Cook (2004) to be **Turing-complete** — capable, in principle, of simulating any computation any computer can perform, given unbounded space and time. It is the simplest known Turing-complete 1D cellular automaton, and sits in Wolfram's Class IV.

Rules 30, 90, and 110 are the standard textbook examples of Classes III, (II/III), and IV respectively — the three qualitatively distinct regimes a deterministic local rule can settle into.

---

## 3. Why Rule 30 looks random

Rule 30 is not merely *visually* irregular: its center column behaves like a random sequence under standard statistical tests. It is, however, **deterministic** — every bit is fixed by the rule — so this is *apparent* randomness (pseudo-randomness), not genuine randomness, and none of it is proven.

- The bit sequence down the pyramid's **center column** behaves like a random sequence in standard statistical tests (roughly equal numbers of 0s and 1s, negligible short-range autocorrelation). This has been **observed** over very long stretches of the column; it has **not been proven**
- Rule 30 was used for integer random-number generation in Mathematica, in versions before 6.0. It remains available there as the `Rule30CA` method, but the current default generator is a different one
- Unlike conventional pseudorandom number generators (linear congruential generators, LFSRs, etc.), which achieve randomness through modular arithmetic on large numbers, Rule 30 achieves it through **pure local interaction** — no multiplication, no modulus, no seed beyond a single bit

**What is not known.** In 2019 Wolfram announced prizes for three open questions about the center column: does it ever become periodic? does each color occur equally often on average? does computing its *n*-th cell require at least about *n* steps of work? To the best of our knowledge they remain unsolved, so this document makes no claim of a proof of randomness.

**Only the center column.** The conjectured randomness concerns the center column. The rest of the triangle has visible structure (for example, its left edge is always Alive — see §7).

**Not for security.** The pattern on the site is fixed and public, so it must never be used where unpredictability matters (keys, lotteries, anything an adversary could exploit).

The **Random Number Generator** panel on the site demonstrates the center column directly: it reads real bits from the center column of *this specific pyramid* and turns them into a number, live. The bits come only from the pattern; the one random choice, the length of the window (§4), is made in the browser.

### Computational irreducibility

A deeper structural fact, central to Wolfram's *A New Kind of Science* (2002): for a Class III/IV rule like Rule 30, there is (as far as is known) **no shortcut** to computing the state at generation *n* other than actually simulating all *n* preceding generations one by one. No closed-form formula exists to "jump ahead." Wolfram calls this property **computational irreducibility** — it is the formal sense in which a system built from a trivial rule can nonetheless be irreducibly complex, not merely complicated-looking.

---

## 4. The Random Number Generator, visualized

The **Random Number Generator** panel on the site is not a separate, disconnected feature — it is a direct, visual demonstration of §3, running on the exact pyramid you see.

### How it works

1. A window of `k` consecutive bits (`k` chosen at random between 8 and 16 on each run, so the output range varies) is read from the **center column** of the pyramid — the same column whose statistical properties are discussed in §3
2. Those `k` bits are read as a binary number and displayed
3. The starting row of the window advances by 5 on every click, so repeated generations sweep down through the pyramid rather than repeating the same bits

### The visual proof

What makes this more than a number generator is that it **shows its own work**: when you click "Generate," the exact cells that produced the number are highlighted in gold directly on the pyramid, and the view briefly zooms in on that portion of the center column. Nothing is hidden or computed off-screen — the number displayed is visibly, traceably, the sequence of Alive/Dead states of those specific agents. This is the clearest illustration on the site of the claim made in §3: Rule 30's randomness is not asserted, it is *shown*, cell by cell.

Note that this generator is entirely independent of the mint mechanism (§5). Clicking "Generate" costs nothing, mints nothing, and does not interact with the smart contract in any way — it runs client-side, reading the same deterministic Rule 30 pattern the pyramid itself is built from. For the same reason it is fully predictable — the same rows always give the same number — so it is a demonstration, not a source of unpredictable randomness.

---

## 5. What kind of mechanism is the mint, precisely?

It's worth being precise here, since blockchain terminology is easy to misapply.

**This is not Proof of Work.** Proof of Work is a specific *consensus mechanism*: the process by which miners on a blockchain compete to solve a cryptographic puzzle in order to validate blocks and secure the network (Bitcoin, and Ethereum before "The Merge" in 2022, both once worked this way). Ethereum today runs on **Proof of Stake**, and minting an agent through this contract involves no cryptographic puzzle-solving by the user whatsoever.

What actually happens is more accurately described as a **paid, deterministic, on-chain generative mint**:

- **Paid** — the minter sends a fixed amount of ETH per agent (see §10)
- **Deterministic** — the Alive/Dead state of the agent being minted is not random, and is not assigned by the contract at mint time; it was already fixed the moment Rule 30 was defined, long before any minting occurred
- **On-chain generative** — the state is not stored data copied from somewhere: the contract can **compute it, in Solidity, on demand**. `getCellState(row, col)` evaluates Rule 30 from the apex and returns the cell's state, as a free read for anyone (§8.1). **The mint itself does not run this computation.** `mint()` and `mintBatch()` only check that the cell is inside the pyramid, outside the founder's zone and not yet minted. The Alive/Dead state has no effect on the price, on the tokens received (3,000 $R30 per agent) or on any other rule of the contract. What the on-chain function provides is **verifiability**: anyone can check that the state shown on the site is the one Rule 30 gives.

So while "mint" describes a financial/ownership transaction, the mathematical object attached to the agent — its Alive/Dead state — is the unmodified output of a real cellular automaton, which the EVM can recompute and confirm at any time.

---

## 6. Why "agent," precisely

Each cell in the pyramid is called an **agent** because it literally implements the canonical **perceive → decide → act** loop used to define agents in artificial intelligence:

```
perceive:  read the states of your left and right neighbors (and yourself)
decide:    look up f(L, C, R) in the rule's transition table
act:       become the resulting state for the next generation
```

This is not a metaphor loosely bolted onto a grid of squares — it is a literal, one-line description of what the local transition function `f` does at every single cell, every single generation. A cellular automaton *is*, mathematically, a synchronous multi-agent system: thousands of identical, simple agents, each with a 3-bit sensory window onto its immediate environment, all executing the same decision rule at once, with the chaotic (or fractal, or computational) global pattern emerging purely from those local interactions — no agent has any knowledge of, or access to, the pattern as a whole.

### A biological precedent

The pigmentation pattern on the shell of the cone snail ***Conus textile*** closely matches the pattern generated by Rule 30. The snail's pigment-secreting cells are believed to interact with their immediate neighbors during shell growth in a way that is mathematically analogous to an elementary cellular automaton: each cell "decides" whether to deposit pigment based on the state of nearby cells moments earlier. It is one of the few well-documented cases of a Wolfram-class rule appearing to run, unassisted, in a living organism — millions of years before Wolfram described it mathematically.

---

## 7. From mathematics to the pyramid

The project's pyramid is a **triangular grid of 10,000 agents**:

- **100 rows**, indexed 0 to 99
- Row *r* contains **2r + 1** agents, centered
- Total agent count: `1 + 3 + 5 + ... + 199 = Σ(2r+1) for r=0..99 = 100² = 10,000`

(This follows from the standard identity that the sum of the first *n* odd numbers is *n²* — the same identity the smart contract exploits for O(1) coordinate indexing in §8.2.)

Each agent's state is fully determined by Rule 30, starting from a single live agent at the apex. Because the rule is deterministic, the entire 10,000-agent pattern is fixed and identical for every visitor — it is not randomized per-user, and minting cannot alter it. Minting only changes *who owns* a given agent; it can never change *what* that agent is.

Counting every cell of this specific pyramid gives:

- **5,196 Alive agents** (52.0%) and **4,804 Dead agents** (48.0%)
- Founder's zone (the first 3,000 indices, §8.2): 1,590 Alive / 1,410 Dead
- Public zone (the other 7,000): 3,606 Alive / 3,394 Dead

The split is close to 50/50 but not exact, and it should not be read as a confirmation of §3, which concerns the center column only. The rest of the triangle has visible structure: the **leftmost cell of every row is always Alive** (100 cells), and the pattern is slightly denser on the left (about 54% Alive in the left third of each row, about 50% in the middle third and 51% in the right third).

---

## 8. Smart contract design (`Rule30` contract, `R30_13.sol`)

The contract implements this pyramid as an ERC-20 token ($R30) with a mint mechanism organised on the Rule 30 pyramid: one claimable agent per cell.

### 8.1 On-chain Rule 30 computation

Rather than storing the entire 10,000-agent grid in contract storage (expensive), the contract computes any row **on demand**:

```solidity
function getRowBits(uint8 targetRow) public pure returns (uint256) {
    uint256 bits = uint256(1) << CENTER;
    for (uint8 r = 0; r < targetRow; r++) {
        bits = _nextRow(bits);
    }
    return bits;
}
```

Each row is packed into a 256-bit integer, bit *i* holding the state of column *i* (columns 0 to 200 are used). `_nextRow` loops over the 201 columns: for each one it reads the left, center and right bits with shifts and masks, forms the 3-bit neighborhood, and looks up the result in the constant `30` (`(30 >> idx) & 1`) — a direct translation of the transition table in §2. Cells beyond the edges count as 0, which never matters here: the pattern spreads one column per row, so it stays inside the 201 columns for all 100 rows.

`getRowBits` and `getCellState` are `pure` functions: they use no storage and nobody pays gas when they are called as a read. They are **not** called when minting (§5), and the site does **not** use them to draw the pyramid: it computes the same pattern in JavaScript so that it can draw instantly. The on-chain functions are there so that anyone can verify it.

Cost note: `getRowBits(99)` runs the 201-column loop 99 times (about 20,000 iterations), and `getCellState` recomputes from row 0 on every call. That is fine as a free read from a wallet or a script, but heavy for another contract to call.

### 8.2 Coordinate indexing

To reserve a specific, deterministic set of agents for the project founder without writing thousands of storage entries, the contract converts every (row, col) pair into a single linear index using the *n²* identity from §7:

```solidity
function _coordsToIndex(uint8 row, uint16 col) internal pure returns (uint256) {
    uint256 r = uint256(row);
    uint16 rowStart = CENTER - row;
    uint256 offset = uint256(col - rowStart);
    return r * r + offset;
}
```

The first `OWNER_AGENTS` (3,000) indices — rows 0 to 53 in full (2,916 cells) plus the leftmost 84 cells of row 54 — are permanently reserved for the founder's allocation. Because this zone is fixed and known in advance, claiming it does not require 3,000 individual storage writes: `ownerMintAll()` sets a few variables (`ownerAgentsMinted`, `allocationHolder`, `totalAgentsMinted`) and credits the tokens in a single balance update, at a fraction of the gas cost a naive per-cell loop would require. Once it has been called, `isAgentMinted` and `agentOwnerOf` treat the whole zone as minted and owned by `allocationHolder`.

### 8.3 Mint mechanics

- `mint(row, col)` — mints one agent for `mintPrice` (0.01 ETH at deployment); any excess ETH is refunded. It reverts with “Mint not started” until the owner has called `startMint()`. Reverts if the cell is outside the pyramid, inside the founder's reserved zone, or already minted
- `mintBatch(rows[], cols[])` — mints up to `MAX_BATCH_SIZE` = 10 agents in one transaction, at `mintPrice × quantity`. It is **all-or-nothing**: if one cell is invalid or already taken, the whole transaction reverts (the site checks this beforehand, §9.1)
- `ownerMintAll()` — one-time, owner-only function that claims the 3,000-agent founder allocation and mints 9,000,000 $R30 straight to the owner's wallet (recorded as `allocationHolder`). It reverts if the mint is already closed
- `startMint()` — owner-only, one-time and **irreversible**: opens the public mint. Until it is called, the owner can still adjust `mintPrice` with `setMintPrice` (never above `MAX_MINT_PRICE` = 0.015 ETH) and replace the liquidity wallet with `setLiquidityWallet`. **From that call on, the mint price and the liquidity wallet are locked forever**
- Each public mint forwards its ETH price immediately to `liquidityWallet`; if that transfer fails, the mint reverts
- Supply is hard-capped at 10,000 agents / 30,000,000 $R30. `mintClosed` becomes `true` automatically when `totalAgentsMinted` reaches 10,000 — which also requires `ownerMintAll()` to have been called, since the public can claim at most 7,000 agents
- `closeMint()` — owner-only emergency stop, usable at any time: closes the mint immediately, even if agents remain unsold, which then opens the market with the agents minted so far. **If it is called before `ownerMintAll()`, the founder allocation can no longer be claimed**, because `ownerMintAll()` reverts once the mint is closed
- **Agents vs tokens.** `agentOwner[row][col]` records the minter permanently and cannot be transferred. The $R30 tokens are an ordinary ERC-20 and can be freely transferred, so selling $R30 does not transfer an agent
- **Secondary market.** `R30Market` (a separate contract) accepts new listings and purchases only once `mintClosed()` is `true`; cancelling a listing is always possible

### 8.4 Security properties

- **Reentrancy guard** on `mint`, `mintBatch`, `ownerMintAll` and `withdraw`, the functions that move ETH or credit tokens during the mint; contract state is updated before any ETH is sent
- **Triangle bounds check** — a cell must satisfy `col ∈ [CENTER − row, CENTER + row]` to be considered part of the pyramid at all
- **Owner-zone protection** — the public `mint()` and `mintBatch()` explicitly reject any coordinate whose linear index falls below `OWNER_AGENTS`, regardless of whether the owner has claimed it yet, eliminating any race condition between founder and public mints
- **Owner powers, until ownership is renounced:** `ownerMintAll()`, `startMint()`, `closeMint()`, `setMintPrice(newPrice)` and `setLiquidityWallet(newWallet)` (both only before `startMint()`, the price being capped at 0.015 ETH), `withdraw()` (sends any ETH left in the contract to `liquidityWallet`; the contract has no `receive()` function, so only a forced send can leave ETH in it) and `transferOwnership(newOwner)` (one step, without confirmation from the new owner). None of them can change a cell's state, take an agent from its owner or move anyone's $R30
- **`renounceOwnership()`** — permanently removes all the owner powers above, so that price, wallet and closure can never change again. **The contract enforces that the mint is finished**: `renounceOwnership()` reverts with “Mint not complete” until `mintClosed()` is `true` (sold out, or closed with `closeMint()`). This guarantees that `startMint()` and `ownerMintAll()` can no longer be left undone, and that the market can always open
- **Liquidity wallet** — it must be able to receive ETH, otherwise every mint reverts; from the moment `startMint()` is called it can no longer be replaced

---

## 9. The mint process, on the site

The smart contract exposes raw functions (`mint`, `mintBatch`); the front-end wraps them in a concrete step-by-step flow:

1. **Select an agent.** Click any available cell on the pyramid directly, or use one of the four helper buttons — *Mint Alive Agent*, *Mint Dead Agent*, *Mint Next Agent*, *Mint Random Agent* — which each search the pyramid (skipping the founder's reserved zone, §8.2) for a cell matching the requested criterion
2. **Choose a quantity (optional).** The quantity slider (1–10) lets a single transaction target several agents at once; the buttons above automatically pick that many matching cells, and the on-screen cost updates live (`quantity × mintPrice`)
3. **Confirm.** A modal displays the exact coordinates, Alive/Dead state, and total $R30 reward before anything is sent. This is purely informational — no request is made to the network yet
4. **Last check before sending.** When the user presses *Mint on Ethereum*, the site first re-reads the chosen cells from the contract and simulates the transaction. If someone else minted one of the chosen agents in the meantime, **nothing is sent**: the cell is replaced (batches only) and the user reviews the list and presses Mint again — details in §9.1
5. **Sign the transaction.** Once the last check passes, the site calls `contract.mint(row, col)` for a single agent, or `contract.mintBatch(rows[], cols[])` for a quantity greater than one, via the connected wallet (MetaMask or Phantom). The wallet displays the exact ETH cost, including network gas, before the user signs
6. **On-chain confirmation.** Once the transaction is mined, the contract:
   - Verifies the cell(s) are inside the pyramid, outside the founder's reserved zone, and not already minted
   - Transfers the ETH mint price to the project's liquidity wallet
   - Mints `3,000 × quantity` $R30 to the caller
   - Emits an `AgentMinted` event for each agent
7. **Front-end update.** The site listens for these events and, without needing a page refresh, marks the newly minted cell(s) red on the pyramid, updates the live supply counters, logs the transaction (with a colored swatch showing whether the agent was Alive or Dead), adds the agent to the connected wallet's personal collection ("My Agents"), and offers to add the $R30 token to the user's wallet automatically

If the site is closed and reopened later, it may first draw the last state saved in the browser (`localStorage`) so that the page appears instantly. It then re-reads `totalAgentsMinted` and scans `isAgentMinted` across the pyramid directly from the contract and corrects what is shown, so the on-chain state is the source of truth and the saved copy is only a speed-up.

### 9.1 Last check before sending: when someone else minted first

Several people can pick cells at the same time, and a cell chosen a minute ago may already belong to someone else. Because `mintBatch` is all-or-nothing, one taken cell would make the whole transaction revert. To avoid that, the front-end runs a check at the moment the user presses *Mint on Ethereum* (the button reads "Checking agents..." while it runs):

1. **Re-read the cells.** `isAgentMinted(row, col)` is called for every chosen cell, in parallel, through the connected wallet. If this read cannot be made (network error), this step is skipped and step 3 still protects the user.
2. **Handle the cells that were just taken.** They are marked as minted and the pyramid is redrawn. Then:
   - **A single agent:** the window closes and a message asks the user to pick another cell. Nothing is sent.
   - **A batch:** the free cells are kept, and each taken cell is replaced by another cell (rules below). Nothing is sent either: the window reopens with the new list and an orange notice, for example *"2 agents were just minted by someone else and replaced by 2 others. Nothing was sent: check the list, then press Mint again."* The user must press Mint again, which runs the check again, so the replacements are verified as well. The previous notice is removed every time the window opens.
   - **No cell left to replace the taken ones:** a message says so and nothing is sent.
3. **Dry run.** The transaction is simulated (`staticCall` of `mint` or `mintBatch`) from the user's wallet, with the exact value (`mintPrice × quantity`). If it would fail — for example because of an insufficient balance — the reason is shown and nothing is sent, so no gas is spent.

**How a replacement cell is chosen.** It is picked at random among the cells that are free, outside the founder's reserved zone (§8.2), and not already in the batch. It must have the **same Alive/Dead state** as the cell it replaces, so a batch keeps the same mix of Alive and Dead agents. It is a random cell from the whole pyramid, not the nearest neighbour. This preference for the same state is a feature of the front-end only: the contract itself only checks that the cell is inside the pyramid, outside the founder's zone and not already minted.

**Known limits**
- If no free cell of the same state is left, a cell of the other state is used instead, and the notice does not say so. The user should check the Alive/Dead state in the list before pressing Mint again.
- The check is not atomic. A cell can still be minted between the check and the inclusion of the transaction in a block. In that case the contract reverts the whole transaction: no agent is minted and no mint price is transferred (only the network gas of a failed transaction can be lost).
- The check never blocks a mint because of its own failure (for example a network error while reading): the wallet and the contract remain the final protection.

---

## 10. Tokenomics summary

| Parameter | Value |
|---|---|
| Token name / symbol | Rule 30 / R30 |
| Max supply | 30,000,000 $R30 |
| Tokens per agent | 3,000 $R30 |
| Total agents (pyramid cells) | 10,000 |
| Founder allocation | 3,000 agents (30%), top of pyramid, free; 9,000,000 $R30 minted to the owner wallet at once, with no lock-up or vesting in the contract. It is the founder's share and is also meant to fund liquidity, exchange listings and token burns. The contract has no burn function (a transfer to the zero address is refused), so a burn is a transfer to a dead address: it does not lower `totalSupply()` |
| Public allocation | 7,000 agents (70%), 0.01 ETH each (set before `startMint()`, never above 0.015 ETH, then locked forever, §8.3 and §8.4) |
| Mint proceeds | Forwarded immediately to the liquidity wallet |
| Underlying pattern | Rule 30 elementary cellular automaton |

---

## References

- S. Wolfram, "Statistical Mechanics of Cellular Automata," *Reviews of Modern Physics* 55, 1983.
- S. Wolfram, *A New Kind of Science*, Wolfram Media, 2002.
- M. Cook, "Universality in Elementary Cellular Automata," *Complex Systems* 15, 2004.
- Wolfram Research, documentation on `Random Integer` generation via Rule 30 (Mathematica).
- S. Wolfram, "Announcing the Rule 30 Prizes," 1 October 2019, writings.stephenwolfram.com.
- E. W. Weisstein, "Rule 30," MathWorld — A Wolfram Resource.
