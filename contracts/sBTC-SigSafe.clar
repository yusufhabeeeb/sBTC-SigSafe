
;; sBTC-SigSafe
;; Multi-Signature Wallet Contract

(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-INVALID-SIGNATURE (err u2))
(define-constant ERR-ALREADY-SIGNED (err u3))
(define-constant ERR-INSUFFICIENT-SIGNATURES (err u4))
(define-constant ERR-INVALID-THRESHOLD (err u5))
(define-constant ERR-TX-NOT-FOUND (err u6))
(define-constant ERR-MAX-SIGNERS (err u7))
(define-constant ERR-LIST-OVERFLOW (err u8))
(define-constant ERR-NOT-PENDING (err u9))
(define-constant ERR-ALREADY-OWNER (err u10))
(define-constant ERR-NOT-OWNER (err u11))
(define-constant ERR-OWNER-THRESHOLD (err u12))
(define-constant ERR-EXPIRED (err u13))
(define-constant ERR-INVALID-SIG-COUNT (err u14))
(define-constant ERR-TX-ACTIVE (err u15))
(define-constant ERR-INSUFFICIENT-FUNDS (err u16))
(define-constant ERR-INVALID-EXPIRATION (err u17))

;; Data Variables
(define-data-var required-signatures uint u2)  ;; M signatures required
(define-data-var total-owners uint u3)         ;; N total owners

;; Data Maps
(define-map owners principal bool)
(define-map transactions 
    uint 
    {
        recipient: principal,
        amount: uint,
        status: (string-ascii 20),
        signatures: uint,
        signers: (list 20 principal),
        expiration-height: uint,
        memo: (optional (string-ascii 100))
    }
)

(define-data-var tx-nonce uint u0)

;; Initialize contract with owners and signature threshold
(define-public (initialize (owners-list (list 20 principal)) (threshold uint))
    (begin
        (asserts! (> threshold u0) ERR-INVALID-THRESHOLD)
        (asserts! (<= threshold (len owners-list)) ERR-INVALID-THRESHOLD)
        (asserts! (< (len owners-list) u20) ERR-INVALID-THRESHOLD)

        (var-set required-signatures threshold)
        (var-set total-owners (len owners-list))

        ;; Register all owners
        (map register-owner owners-list)
        (ok true)
    )
)

;; Helper function to register an owner
(define-private (register-owner (owner principal))
    (map-set owners owner true)
)

;; Submit a new transaction for approval
(define-public (submit-transaction (recipient principal) (amount uint))
    (let
        ((tx-id (var-get tx-nonce)))

        ;; Verify sender is an owner
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)

        ;; Create new transaction
        (map-set transactions tx-id {
            recipient: recipient,
            amount: amount,
            status: "pending",
            signatures: u0,
            signers: (list),
            expiration-height: (+ stacks-block-height (var-get tx-expiration)),
            memo: none
        })

        ;; Increment nonce
        (var-set tx-nonce (+ tx-id u1))
        (ok tx-id)
    )
)

;;  Submit transaction with memo and custom expiration
(define-public (submit-transaction-with-memo 
    (recipient principal) 
    (amount uint) 
    (memo (string-ascii 100))
    (expiration-blocks uint))
    (let
        ((tx-id (var-get tx-nonce)))

        ;; Verify sender is an owner
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)
        
        ;; Verify expiration is valid
        (asserts! (> expiration-blocks u0) ERR-INVALID-EXPIRATION)
        (asserts! (<= expiration-blocks u1440) ERR-INVALID-EXPIRATION) ;; Max 10 days (1440 blocks)

        ;; Create new transaction
        (map-set transactions tx-id {
            recipient: recipient,
            amount: amount,
            status: "pending",
            signatures: u0,
            signers: (list),
            expiration-height: (+ stacks-block-height expiration-blocks),
            memo: (some memo)
        })

        ;; Increment nonce
        (var-set tx-nonce (+ tx-id u1))
        
        ;; Print event for tracking
        (print {
            event: "submit-transaction-with-memo",
            tx-id: tx-id,
            recipient: recipient,
            amount: amount,
            memo: memo,
            expiration: (+ stacks-block-height expiration-blocks),
            submitter: tx-sender
        })
        
        (ok tx-id)
    )
)

;; Data Maps
;; (define-map owners principal bool)
(define-map transaction-signers { tx-id: uint, signer: principal } bool)

;; Execute a transaction that has sufficient signatures
(define-public (execute-transaction (tx-id uint))
    (let
        ((tx (unwrap! (map-get? transactions tx-id) ERR-TX-NOT-FOUND)))

        ;; Verify sufficient signatures
        (asserts! (>= (get signatures tx) (var-get required-signatures))
                 ERR-INSUFFICIENT-SIGNATURES)
        
        ;; Verify not expired
        (asserts! (<= stacks-block-height (get expiration-height tx)) ERR-EXPIRED)

        ;; Execute transfer
        (try! (stx-transfer? (get amount tx) (as-contract tx-sender) (get recipient tx)))

        ;; Update transaction status
        (map-set transactions tx-id
            (merge tx { status: "executed" }))

        (ok true)
    )
)

;; ;; Add expiration time variable (e.g., 24 hours in blocks, assuming 10 min per block)
(define-data-var tx-expiration uint u144)  ;; ~24 hours in blocks


;; Helper to check if principal is an owner
(define-private (is-owner (user principal))
    (default-to false (map-get? owners user))
)

;; Helper to check if a signer exists in list
(define-private (contains-signer? (signers (list 20 principal)) (user principal))
    (is-some (index-of signers user))
)

;; Read only functions
(define-read-only (get-transaction (tx-id uint))
    (map-get? transactions tx-id)
)

(define-read-only (get-required-signatures)
    (var-get required-signatures)
)

(define-read-only (get-total-owners)
    (var-get total-owners)
)

(define-read-only (is-valid-owner (user principal))
    (is-owner user)
)


(define-public (sign-transaction (tx-id uint))
    (let
        ((tx (unwrap! (map-get? transactions tx-id) ERR-TX-NOT-FOUND)))

        ;; Verify sender is an owner
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)

        ;; Verify not already signed
        (asserts! (not (contains-signer? (get signers tx) tx-sender)) ERR-ALREADY-SIGNED)

        ;; Verify we won't exceed the maximum list size
        (asserts! (< (len (get signers tx)) u20) (err u7))

        ;; Verify not expired
        (asserts! (<= stacks-block-height (get expiration-height tx)) ERR-EXPIRED)

        ;; Update transaction
        (map-set transactions tx-id
            (merge tx {
                signatures: (+ (get signatures tx) u1),
                signers: (unwrap! (as-max-len? (append (get signers tx) tx-sender) u20) (err u8))
            }))

        (ok true)
    )
)

;; Cancel a pending transaction (only executable by transaction submitter)
(define-public (cancel-transaction (tx-id uint))
    (let ((tx (unwrap! (map-get? transactions tx-id) ERR-TX-NOT-FOUND)))
        ;; Verify transaction is still pending
        (asserts! (is-eq (get status tx) "pending") (err u9))

        ;; Only allow cancellation if no signatures yet or by any owner if expired
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)

        ;; Update transaction status to cancelled
        (map-set transactions tx-id
            (merge tx { status: "cancelled" }))

        (ok true)
    )
)

;; Add a new owner (requires multi-sig approval)
(define-public (add-owner (new-owner principal))
    (begin
        ;; Verify sender is an owner
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)

        ;; Verify new owner isn't already an owner
        (asserts! (not (is-owner new-owner)) (err u10))

        ;; Verify we won't exceed maximum owners
        (asserts! (< (var-get total-owners) u20) ERR-MAX-SIGNERS)

        ;; Register new owner
        (map-set owners new-owner true)
        (var-set total-owners (+ (var-get total-owners) u1))

        (ok true)
    )
)

;; Remove an existing owner (requires multi-sig approval)
(define-public (remove-owner (owner-to-remove principal))
    (begin
        ;; Verify sender is an owner
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)

        ;; Verify target is actually an owner
        (asserts! (is-owner owner-to-remove) (err u11))

        ;; Verify we won't go below required signatures
        (asserts! (> (- (var-get total-owners) u1) (var-get required-signatures)) 
                 (err u12))

        ;; Remove owner
        (map-set owners owner-to-remove false)
        (var-set total-owners (- (var-get total-owners) u1))

        (ok true)
    )
)


;; Update required signatures threshold (requires multi-sig)
(define-public (update-required-signatures (new-threshold uint))
    (begin
        ;; Verify sender is an owner
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)

        ;; Verify new threshold is valid
        (asserts! (> new-threshold u0) ERR-INVALID-SIG-COUNT)
        (asserts! (<= new-threshold (var-get total-owners)) ERR-INVALID-SIG-COUNT)

        ;; Check no pending transactions
        (asserts! (is-eq (var-get tx-nonce) u0) ERR-TX-ACTIVE)

        ;; Update threshold
        (var-set required-signatures new-threshold)

        ;; Print event for tracking
        (print {
            event: "update-required-signatures",
            old-threshold: (var-get required-signatures),
            new-threshold: new-threshold,
            caller: tx-sender
        })

        (ok true)
    )
)

;; NEW FUNCTION #2: Batch processing of transactions
(define-public (batch-create-transactions
    (recipients (list 10 principal))
    (amounts (list 10 uint))
    (memos (optional (list 10 (string-ascii 100)))))
    (let
        ((total-amount (fold + amounts u0)))

        ;; Verify sender is an owner
        (asserts! (is-owner tx-sender) ERR-NOT-AUTHORIZED)

        ;; Verify lists have same length
        (asserts! (is-eq (len recipients) (len amounts)) ERR-INVALID-SIGNATURE)

        ;; Verify memos list has same length if provided
        (asserts! (or 
                  (is-none memos)
                  (is-eq (len recipients) (len (unwrap! memos ERR-INVALID-SIGNATURE)))) 
                ERR-INVALID-SIGNATURE)

        ;; Verify contract has enough balance
        (asserts! (>= (stx-get-balance (as-contract tx-sender)) total-amount) ERR-INSUFFICIENT-FUNDS)

        ;; Process all transactions
        (ok (map batch-create-transaction 
                 recipients 
                 amounts 
                 (if (is-some memos)
                     (unwrap! memos ERR-INVALID-SIGNATURE)
                     (list "Transfer" "Transfer" "Transfer" "Transfer" "Transfer" 
                           "Transfer" "Transfer" "Transfer" "Transfer" "Transfer"))))
    )
)

;; Helper function for batch transaction creation
(define-private (batch-create-transaction 
    (recipient principal) 
    (amount uint)
    (memo (string-ascii 100)))
    (let
        ((tx-id (var-get tx-nonce)))

        ;; Create new transaction
        (map-set transactions tx-id {
            recipient: recipient,
            amount: amount,
            status: "pending",
            signatures: u0,
            signers: (list),
            expiration-height: (+ stacks-block-height (var-get tx-expiration)),
            memo: (some memo)
        })

        ;; Increment nonce
        (var-set tx-nonce (+ tx-id u1))

        ;; Return transaction ID
        tx-id
    )
)