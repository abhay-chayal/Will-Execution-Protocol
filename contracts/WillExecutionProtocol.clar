;; WillExecution Protocol
;; Digital will management with beneficiary notifications and asset distribution automation
;; A smart contract for creating and executing digital wills on Stacks blockchain

;; Define constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-will-not-found (err u102))
(define-constant err-will-already-executed (err u103))
(define-constant err-invalid-amount (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-will-not-ready (err u106))

;; Data structures
;; Will structure to store will information
(define-map wills principal {
  testator: principal,
  beneficiary: principal,
  asset-amount: uint,
  execution-block: uint,
  is-executed: bool,
  created-at: uint
})

;; Beneficiary notifications
(define-map notifications principal {
  will-creator: principal,
  notification-sent: bool,
  asset-amount: uint,
  execution-block: uint
})

;; Track total wills created
(define-data-var total-wills uint u0)

;; Function 1: Create Will
;; Allows users to create a digital will specifying beneficiary and execution conditions
(define-public (create-will (beneficiary principal) (asset-amount uint) (execution-delay-blocks uint))
  (let ((current-block stacks-block-height)
        (execution-block (+ current-block execution-delay-blocks)))
    (begin
      ;; Validate inputs
      (asserts! (> asset-amount u0) err-invalid-amount)
      (asserts! (> execution-delay-blocks u0) err-invalid-amount)
      (asserts! (>= (stx-get-balance tx-sender) asset-amount) err-insufficient-balance)
      
      ;; Lock the STX amount in the contract
      (try! (stx-transfer? asset-amount tx-sender (as-contract tx-sender)))
      
      ;; Create the will record
      (map-set wills tx-sender {
        testator: tx-sender,
        beneficiary: beneficiary,
        asset-amount: asset-amount,
        execution-block: execution-block,
        is-executed: false,
        created-at: current-block
      })
      
      ;; Create notification for beneficiary
      (map-set notifications beneficiary {
        will-creator: tx-sender,
        notification-sent: true,
        asset-amount: asset-amount,
        execution-block: execution-block
      })
      
      ;; Update total wills counter
      (var-set total-wills (+ (var-get total-wills) u1))
      
      ;; Print event for indexing
      (print {
        event: "will-created",
        testator: tx-sender,
        beneficiary: beneficiary,
        amount: asset-amount,
        execution-block: execution-block
      })
      
      (ok true))))

;; Function 2: Execute Will
;; Allows beneficiaries to claim their inheritance after execution conditions are met
(define-public (execute-will (testator principal))
  (let ((will-data (unwrap! (map-get? wills testator) err-will-not-found)))
    (begin
      ;; Verify execution conditions
      (asserts! (is-eq tx-sender (get beneficiary will-data)) err-not-authorized)
      (asserts! (not (get is-executed will-data)) err-will-already-executed)
      (asserts! (>= stacks-block-height (get execution-block will-data)) err-will-not-ready)
      
      ;; Transfer assets to beneficiary
      (try! (as-contract (stx-transfer? (get asset-amount will-data) tx-sender (get beneficiary will-data))))
      
      ;; Mark will as executed
      (map-set wills testator (merge will-data {is-executed: true}))
      
      ;; Print execution event
      (print {
        event: "will-executed",
        testator: testator,
        beneficiary: (get beneficiary will-data),
        amount: (get asset-amount will-data),
        executed-at: stacks-block-height
      })
      
      (ok true))))

;; Read-only functions for querying will information
(define-read-only (get-will (testator principal))
  (map-get? wills testator))

(define-read-only (get-notification (beneficiary principal))
  (map-get? notifications beneficiary))

(define-read-only (get-total-wills)
  (var-get total-wills))

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))

;; Check if will is ready for execution
(define-read-only (is-will-executable (testator principal))
  (match (map-get? wills testator)
    will-data (and 
                (not (get is-executed will-data))
                (>= stacks-block-height (get execution-block will-data)))
    false))