# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:
>The risk is that minting authority also permits destroying another holder's tokens without consent. Ex4 demonstrates this permission by impersonating the vault in the test environment. This does not prove that an ordinary user can make the existing vault burn arbitrary accounts: its current redemption function burns only the caller's balance. Nevertheless, the token gives the vault unnecessarily broad authority.
>
> I would remove the privileged burn(address,uint256) function from SimpleStablecoin and replace it with an allowance-based burnFrom(owner,amount). This function would require the designated vault as caller, consume the owner's allowance to that vault, and then burn the approved amount. Minting permission would no longer imply unrestricted burning. OpenZeppelin's ERC20Burnable provides the allowance-consumption pattern.
>
> In Vault.redeem(amount), the owner would remain msg.sender. The vault would call burnFrom(msg.sender,amount) and return collateral to the same caller in one atomic transaction. Users would approve only their intended redemption amount; insufficient approval or a failed collateral transfer would revert the operation.
>
> I would test that redemption without approval fails, approved redemption succeeds, and neither the vault nor another minter can burn beyond authorization. This removes unrestricted confiscation, although outstanding approvals still represent trust in the approved spender. 
<br><br><br>

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:
>
>I would separate the roles according to their responsibilities and avoid leaving the deployment account with permanent operational privileges.
>
>DEFAULT_ADMIN_ROLE would belong to a timelock contract controlled by a governance multisignature wallet with independent signers. Changes to privileged accounts would therefore require collective approval and a public delay. The deployer would relinquish its roles after verifying the configuration. OpenZeppelin describes timelocks as a way to make administrative actions reviewable before execution.
>
>MINTER_ROLE would belong only to the audited vault, whose issuance path requires receiving collateral first. A staff wallet would not receive unrestricted minting permission. I would also remove the present connection between minting and arbitrary burning, as described in A1.
>
>PAUSER_ROLE would belong to a separate security multisignature wallet that can respond quickly to incidents but cannot mint tokens or appoint new administrators. I would modify the contract to separate emergency pausing from unpausing, with recovery subject to governance approval after investigation.
>
>These controls reduce dependence on one compromised key. They do not eliminate governance risk: administrators can still change permissions, and a malicious signing quorum remains dangerous. Role-change monitoring and tested recovery procedures are therefore also necessary. 
<br><br><br>

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:
>I would replace the blanket whenNotPaused modifier on _update with checks that distinguish ordinary transfers, minting, and burning. In the ERC-20 update convention, an ordinary transfer has nonzero sender and recipient addresses, minting has a zero sender, and burning has a zero recipient.
>
>During a transfer pause, updates between two nonzero addresses would revert. I would control new issuance with a separate minting pause, while allowing the authorized burn operation required by redemption. Normal balance and authorization checks would remain active; allowing burns would not mean allowing arbitrary users to destroy other holders' balances.
>
>Vault.redeem would continue burning the caller's tokens and returning the corresponding collateral atomically. With the A1 redesign, users would approve the required burn allowance. Redemption would not first transfer sUSD into the vault, because that transfer would be blocked by the transfer pause.
>
>I would test blocked transfers, blocked issuance when configured, successful authorized redemption, rejected unauthorized burns, and restored operation after recovery. Redemption also depends on the collateral token remaining transferable. If the vulnerability is in redemption itself, preserving that path blindly could worsen losses; it needs a separate, explicitly governed emergency control.

<br><br><br>

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:
>
>The comparison needs a factual qualification. In September 2008, the Reserve Primary Fund reported a net asset value of $0.97 per share and delayed redemption payments. The SEC subsequently permitted a broader suspension to support orderly liquidation. This was more than a brief interruption followed by ordinary operation.
>
>Suspending redemption can prevent forced asset sales and reduce the advantage of investors who withdraw first. However, it also prevents holders from converting their claims into cash and weakens confidence in immediate access to reserves.
>
>USDC's 2023 experience was not uninterrupted dollar redemption throughout the crisis weekend. Circle maintained its commitment to dollar parity, but banking disruption constrained processing. By March 15, Circle reported clearing substantially all minting and redemption backlogs and redeeming $3.8 billion since Monday. Restored access to reserves and redemption services helped support recovery.
>
>For a stablecoin, credible redemption creates an arbitrage incentive: eligible traders can buy discounted tokens and redeem them at par, subject to costs and access constraints. Closing that channel weakens this price-restoring mechanism. Nevertheless, keeping redemption available cannot by itself repair insolvent reserves. Reserve quality, available liquidity, credible loss absorption, and fair treatment of remaining holders must also be considered

<br><br><br>

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:
>
>One cause is a reserve shortfall: unauthorized minting increases supply without adding collateral, or collateral is removed without a corresponding reduction in supply. In that situation, totalCollateral() >= totalSupply() becomes false. Ex3 demonstrated this accounting failure, although it did not measure an actual market price.
>
>A second cause is blocked redemption. The vault may hold sufficient collateral while pausing, access restrictions, or an operational failure prevents users from exchanging their tokens. The numerical invariant can remain true even though the arbitrage mechanism supporting the peg is unavailable. Ex4 demonstrates this distinction by blocking redemption while collateral remains in the vault.
>
>A third cause is deterioration in the collateral's value. If one collateral token is worth less than one dollar, equal token quantities no longer guarantee equal dollar values. The invariant may still pass because it compares balances rather than realizable dollar reserves. MockUSDC also has no actual dollar redemption promise in this laboratory.
>
>Therefore, the invariant is a useful backing check under the assumed unit relationship, not a complete proof of price stability. A stronger assessment would combine reserve valuation, liquidity, enforceable redemption rights, operational availability, and control of minting authority.
<br><br><br>

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:
>After obtaining MINTER_ROLE, the attacker calls the stablecoin's mint function directly and receives 1,000,000 sUSD without depositing collateral. Supply rises, while the vault's reserves remain unchanged. The attacker then calls redeem, which burns their sUSD and transfers an equal quantity of mUSDC from the vault to their address.
>
>Redeeming the entire million requires at least one million mUSDC in the vault. In my Ex3 run, supply was 1,000,700 sUSD but reserves were only 700 mUSDC. A single redemption of one million would therefore revert at the insufficient-collateral check. However, the attacker could redeem 700 sUSD and empty those reserves, leaving the remaining holders without backing. The excess fake tokens would remain outstanding.
>
>The earliest preventive step is preventing the inappropriate grant of minting authority. I would restrict issuance to the collateral-receiving vault, remove the deployer's unrestricted minting role, and protect any remaining role administration with multisignature approval and a timelock.
>
>A stronger issuance design would enforce collateral backing even on privileged mint calls. Monitoring and emergency intervention could limit damage if timely, but the existing redemption balance check only prevents overdrawing the vault in one transaction; it does not distinguish legitimately backed tokens from maliciously minted tokens.
<br><br><br>

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:
>
>The same raw token-balance comparison would not be sufficient for US Treasuries. A blockchain balance could represent a claim on securities, but it would not independently prove that the securities exist, are unencumbered, or are legally available to stablecoin holders.
>
>I would instead define backing in dollar terms: conservatively valued, legally available reserve assets, net of other senior claims and expected realization costs, must cover the stablecoin's dollar liabilities. This requires consistent units, verified custody records, reliable valuation data, and protection against counting both a Treasury token and its underlying securities as separate assets.
>
>Treasuries also introduce market and liquidity risks. Fixed-rate bond prices can fall when interest rates rise. Receiving face value at maturity does not guarantee that the same amount can be raised through an earlier sale. Redemption may therefore depend on cash buffers, asset maturities, settlement, and access to intermediaries.
>
>I would require segregated custody, reconciliation of token supply against reserve records, independent attestations, and a documented redemption process. Solvency and immediate liquidity should be monitored separately. These measures improve assurance, but a smart contract or oracle cannot independently establish off-chain ownership, absence of liens, or legal enforceability.

<br><br><br>

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:
>
>A building cannot literally be transferred into a smart contract. I would first define the legal claim represented by the token. For example, a special-purpose vehicle could own the property, while tokens represent specified shares in that vehicle or secured claims against it. Those structures give holders different rights and should not be treated as interchangeable.
>
>The property title and any security interests would need valid registration under the relevant jurisdiction. Legal documents would connect token ownership to the promised economic and enforcement rights, including income distributions, transfer restrictions, default procedures, and the priority of claims. A blockchain transfer would not automatically replace land-registration requirements.
>
>The arrangement would need an issuer or administrator, legal counsel, a title-registration process, independent valuers, a property manager, and a trustee or security agent where appropriate. Bank accounts, insurance, accounting, and independent reviews would support the physical asset and its cash flows.
>
>The vault could accept eligible tokens and apply conservative valuation and borrowing limits. However, selling tokens does not guarantee that the building can be sold quickly. Foreclosure and property sales may take substantial time, so continuous stablecoin redemption would require separate liquid reserves or clearly disclosed redemption terms.
<br><br><br>

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | |
| Transfers revert while paused | |
| **Redemption** reverts while paused | |
| An attacker cannot burn someone else's balance | |
| ...but the vault holding `MINTER_ROLE` can | |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer:

| Scenario | Completed test function |
|---|---|
| Minting by a non-minter reverts | `test_Ex4_Mint_RevertsForNonMinter` |
| Transfers revert while paused | `test_Ex4_Pause_BlocksTransfers` |
| Redemption reverts while paused | `test_Ex4_Pause_BlocksRedeem` |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance` |
| The vault holding MINTER_ROLE can burn another user's balance | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` |

I would prioritize an attempted privilege-escalation attack followed by reserve extraction. An attacker who can turn an ordinary account into a minter can bypass collateral deposits and target every depositor's reserves. I regard this as a particularly consequential scenario because the administrative role controls who may issue tokens; it is a threat-model judgment rather than a claim about measured attack frequency.

A proposed test, test_RoleEscalation_RevertsForNonAdmin, would first create a funded vault through a legitimate user's deposit. It would then impersonate an unprivileged attacker and attempt to grant MINTER_ROLE to that same attacker. The test should require the precise missing-admin-role error, confirm that the attacker still lacks minting authority, and verify unchanged supply and reserves.

A separate adversarial test could model a compromised administrator actually granting the role, followed by unbacked issuance and a redemption limited to available reserves. That would document the remaining governance risk and distinguish it from a broken access-control check.

These are proposed additional tests, not tests already included in my reported passing results.

