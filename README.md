
# sBTC-SigSafe - Multi-Signature Wallet Smart Contract

A secure, extensible multi-signature wallet on the **Stacks blockchain** using the **Clarity smart contract language**. This contract allows for **M-of-N signature approval**, time-bound execution, memo support, owner management, and batch transaction creation — ideal for DAOs, treasuries, and secure multi-party wallets.

---
##  Features

* ✅ **M-of-N signature model** — Require multiple owners to approve transactions.
* 📝 **Transaction memos** — Optional memo support for clarity and context.
* ⏰ **Transaction expiration** — Prevents stale transactions from being executed.
* 🧾 **Batch transaction creation** — Send multiple transfers in one call.
* 🔐 **Owner management** — Add or remove owners with multi-sig governance.
* 🔄 **Signature threshold update** — Change M-of-N settings with safety checks.
* 📜 **Audit-friendly** — Event printing for key actions.

---

## ⚙️ Initialization

### `initialize`

Initializes the wallet with a list of owner principals and a required signature threshold.

```clojure
(define-public (initialize (owners-list (list 20 principal)) (threshold uint)))
```

#### Constraints:

* `threshold > 0`
* `threshold <= length(owners-list)`
* `length(owners-list) < 20`

---

## 💸 Transactions

### `submit-transaction`

Create a new transaction requiring approval.

```clojure
(define-public (submit-transaction (recipient principal) (amount uint)))
```

---

### `submit-transaction-with-memo`

Submit a transaction with an optional memo and expiration.

```clojure
(define-public (submit-transaction-with-memo 
    (recipient principal) 
    (amount uint) 
    (memo (string-ascii 100))
    (expiration-blocks uint)))
```

* `expiration-blocks`: Max 1440 (≈10 days)

---

### `sign-transaction`

Sign an existing transaction as an authorized owner.

```clojure
(define-public (sign-transaction (tx-id uint)))
```

* Prevents double-signing
* Checks expiration

---

### `execute-transaction`

Execute a transaction that meets the signature threshold.

```clojure
(define-public (execute-transaction (tx-id uint)))
```

* Transfers STX to the recipient
* Marks the transaction as "executed"

---

### `cancel-transaction`

Cancel a transaction that is still pending.

```clojure
(define-public (cancel-transaction (tx-id uint)))
```

* Must be an owner
* Only for pending transactions

---

## 📦 Batch Operations

### `batch-create-transactions`

Create multiple transactions in a single call.

```clojure
(define-public (batch-create-transactions
    (recipients (list 10 principal))
    (amounts (list 10 uint))
    (memos (optional (list 10 (string-ascii 100)))))
```

* Verifies lengths match
* Uses default "Transfer" memo if none provided
* Validates available balance

---

## 👥 Owner Management

### `add-owner`

Add a new owner (requires existing owner to call).

```clojure
(define-public (add-owner (new-owner principal)))
```

---

### `remove-owner`

Remove an existing owner.

```clojure
(define-public (remove-owner (owner-to-remove principal)))
```

* Cannot reduce owners below required signatures

---

### `update-required-signatures`

Update M-of-N threshold.

```clojure
(define-public (update-required-signatures (new-threshold uint)))
```

* Fails if there are pending transactions
* Must be within valid owner count bounds

---

## 🧠 Internal and Read-only

* `is-owner`: Private helper to verify owner
* `contains-signer?`: Prevents duplicate signing
* `get-transaction`: View transaction by ID
* `get-required-signatures`, `get-total-owners`, `is-valid-owner`: Read-only getters

---

## ❌ Error Codes

| Code | Description                   |
| ---- | ----------------------------- |
| u1   | Not authorized                |
| u2   | Invalid signature or mismatch |
| u3   | Already signed                |
| u4   | Insufficient signatures       |
| u5   | Invalid threshold             |
| u6   | Transaction not found         |
| u7   | Max signers reached           |
| u8   | List overflow                 |
| u9   | Not pending                   |
| u10  | Already owner                 |
| u11  | Not an owner                  |
| u12  | Signature threshold violation |
| u13  | Transaction expired           |
| u14  | Invalid signature count       |
| u15  | Active transaction exists     |
| u16  | Insufficient funds            |
| u17  | Invalid expiration blocks     |

---

## 📦 Storage Overview

| Variable              | Type                          | Purpose                        |
| --------------------- | ----------------------------- | ------------------------------ |
| `required-signatures` | `uint`                        | M of M-of-N                    |
| `total-owners`        | `uint`                        | Number of owners (N)           |
| `owners`              | `map principal -> bool`       | Track ownership                |
| `transactions`        | `map uint -> struct`          | Transaction records            |
| `transaction-signers` | `map {tx-id, signer} -> bool` | Used for double-signing checks |
| `tx-nonce`            | `uint`                        | Next transaction ID            |
| `tx-expiration`       | `uint`                        | Default transaction expiry     |

---

## 📢 Events

Events are emitted via `print` for:

* `submit-transaction-with-memo`
* `update-required-signatures`

You can extend event logging further for `add-owner`, `remove-owner`, etc.

---

## 🧪 Testing Recommendations

Test for:

* M-of-N logic correctness
* Owner add/remove threshold validation
* Expiration enforcement
* Batch functionality constraints
* Replay attack resistance
* Gas/limit boundaries

---

## ✅ Deployment Checklist

* [ ] Set proper initial owners and threshold
* [ ] Audit `stx-transfer?` logic
* [ ] Gas-check batch limits
* [ ] Optional: add locking or pausing mechanism for governance

---
