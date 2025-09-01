
;; title: treasury-core
;; version: 1.0.0
;; summary: Core treasury management contract for decentralized treasury operations
;; description: Handles cash flow forecasting, liquidity management, and funding operations

;; ========================================
;; ERROR CODES
;; ========================================

(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-AMOUNT (err u402))
(define-constant ERR-INSUFFICIENT-BALANCE (err u403))
(define-constant ERR-INVALID-PERIOD (err u404))
(define-constant ERR-FORECAST-NOT-FOUND (err u405))
(define-constant ERR-LIQUIDITY-POOL-EXISTS (err u406))
(define-constant ERR-LIQUIDITY-POOL-NOT-FOUND (err u407))
(define-constant ERR-FUNDING-REQUEST-EXISTS (err u408))
(define-constant ERR-FUNDING-REQUEST-NOT-FOUND (err u409))
(define-constant ERR-INVALID-STATUS (err u410))

;; ========================================
;; CONSTANTS
;; ========================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-LIQUIDITY-RATIO u10) ;; 10%
(define-constant EMERGENCY-BUFFER-RATIO u20) ;; 20%
(define-constant MAX-FORECAST-PERIODS u12) ;; 12 months
(define-constant BASIS-POINTS u10000) ;; For percentage calculations

;; ========================================
;; DATA VARIABLES
;; ========================================

(define-data-var treasury-balance uint u0)
(define-data-var total-assets uint u0)
(define-data-var total-liabilities uint u0)
(define-data-var emergency-buffer uint u0)
(define-data-var liquidity-ratio uint u0)
(define-data-var next-forecast-id uint u1)
(define-data-var next-pool-id uint u1)
(define-data-var next-funding-id uint u1)
(define-data-var treasury-administrator principal CONTRACT-OWNER)

;; ========================================
;; DATA MAPS
;; ========================================

;; Cash flow forecasts
(define-map cash-flow-forecasts
  uint
  {
    period: uint,
    projected-inflow: uint,
    projected-outflow: uint,
    net-flow: int,
    confidence-score: uint,
    created-at: uint,
    created-by: principal
  }
)

;; Liquidity pools
(define-map liquidity-pools
  uint
  {
    name: (string-ascii 50),
    balance: uint,
    target-ratio: uint,
    current-ratio: uint,
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint
  }
)

;; Funding requests
(define-map funding-requests
  uint
  {
    requester: principal,
    amount: uint,
    purpose: (string-ascii 200),
    urgency: (string-ascii 20),
    status: (string-ascii 20),
    approved-amount: uint,
    created-at: uint,
    processed-at: uint,
    processed-by: (optional principal)
  }
)

;; Authorized signers for multi-sig operations
(define-map authorized-signers principal bool)

;; ========================================
;; PRIVATE FUNCTIONS
;; ========================================

(define-private (is-authorized (user principal))
  (or 
    (is-eq user (var-get treasury-administrator))
    (default-to false (map-get? authorized-signers user))
  )
)

(define-private (calculate-liquidity-ratio (liquid-assets uint) (total-asset-value uint))
  (if (is-eq total-asset-value u0)
    u0
    (/ (* liquid-assets BASIS-POINTS) total-asset-value)
  )
)

(define-private (update-emergency-buffer)
  (let (
    (current-balance (var-get treasury-balance))
    (required-buffer (/ (* current-balance EMERGENCY-BUFFER-RATIO) u100))
  )
    (var-set emergency-buffer required-buffer)
    (ok required-buffer)
  )
)

(define-private (validate-forecast-data (inflow uint) (outflow uint) (period uint))
  (and
    (> inflow u0)
    (> outflow u0)
    (<= period MAX-FORECAST-PERIODS)
  )
)

;; ========================================
;; PUBLIC FUNCTIONS
;; ========================================

;; Initialize treasury with initial balance
(define-public (initialize-treasury (initial-balance uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set treasury-balance initial-balance)
    (var-set total-assets initial-balance)
    (unwrap! (update-emergency-buffer) ERR-INVALID-AMOUNT)
    (map-set authorized-signers CONTRACT-OWNER true)
    (ok initial-balance)
  )
)

;; Add authorized signer
(define-public (add-authorized-signer (signer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get treasury-administrator)) ERR-UNAUTHORIZED)
    (map-set authorized-signers signer true)
    (ok true)
  )
)

;; Remove authorized signer
(define-public (remove-authorized-signer (signer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get treasury-administrator)) ERR-UNAUTHORIZED)
    (map-delete authorized-signers signer)
    (ok true)
  )
)

;; Create cash flow forecast
(define-public (create-cash-flow-forecast (period uint) (projected-inflow uint) (projected-outflow uint))
  (let (
    (forecast-id (var-get next-forecast-id))
    (net-flow (- (to-int projected-inflow) (to-int projected-outflow)))
    (confidence-score (if (> projected-inflow projected-outflow) u85 u70))
  )
    (asserts! (is-authorized tx-sender) ERR-UNAUTHORIZED)
    (asserts! (validate-forecast-data projected-inflow projected-outflow period) ERR-INVALID-PERIOD)
    
    (map-set cash-flow-forecasts forecast-id
      {
        period: period,
        projected-inflow: projected-inflow,
        projected-outflow: projected-outflow,
        net-flow: net-flow,
        confidence-score: confidence-score,
        created-at: block-height,
        created-by: tx-sender
      }
    )
    
    (var-set next-forecast-id (+ forecast-id u1))
    (ok forecast-id)
  )
)

;; Optimize cash flow based on forecasts
(define-public (optimize-cash-flow (forecast-id uint) (optimization-target uint))
  (let (
    (forecast (unwrap! (map-get? cash-flow-forecasts forecast-id) ERR-FORECAST-NOT-FOUND))
    (current-balance (var-get treasury-balance))
    (optimized-amount (if (> optimization-target current-balance)
                        (- optimization-target current-balance)
                        u0))
  )
    (asserts! (is-authorized tx-sender) ERR-UNAUTHORIZED)
    
    ;; Update treasury balance based on optimization
    (if (> optimized-amount u0)
      (var-set treasury-balance (+ current-balance optimized-amount))
      (var-set treasury-balance optimization-target)
    )
    
    (unwrap! (update-emergency-buffer) ERR-INVALID-AMOUNT)
    (ok optimized-amount)
  )
)

;; Create liquidity pool
(define-public (create-liquidity-pool (name (string-ascii 50)) (initial-balance uint) (target-ratio uint))
  (let (
    (pool-id (var-get next-pool-id))
    (current-ratio (calculate-liquidity-ratio initial-balance (var-get total-assets)))
  )
    (asserts! (is-authorized tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> initial-balance u0) ERR-INVALID-AMOUNT)
    (asserts! (<= target-ratio BASIS-POINTS) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? liquidity-pools pool-id)) ERR-LIQUIDITY-POOL-EXISTS)
    
    (map-set liquidity-pools pool-id
      {
        name: name,
        balance: initial-balance,
        target-ratio: target-ratio,
        current-ratio: current-ratio,
        status: "active",
        created-at: block-height,
        updated-at: block-height
      }
    )
    
    (var-set next-pool-id (+ pool-id u1))
    (var-set total-assets (+ (var-get total-assets) initial-balance))
    (ok pool-id)
  )
)

;; Update liquidity pool balance
(define-public (update-liquidity-pool (pool-id uint) (new-balance uint))
  (let (
    (pool (unwrap! (map-get? liquidity-pools pool-id) ERR-LIQUIDITY-POOL-NOT-FOUND))
    (balance-diff (if (> new-balance (get balance pool))
                    (- new-balance (get balance pool))
                    u0))
    (new-ratio (calculate-liquidity-ratio new-balance (var-get total-assets)))
  )
    (asserts! (is-authorized tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> new-balance u0) ERR-INVALID-AMOUNT)
    
    (map-set liquidity-pools pool-id
      (merge pool {
        balance: new-balance,
        current-ratio: new-ratio,
        updated-at: block-height
      })
    )
    
    ;; Update total assets if balance increased
    (if (> balance-diff u0)
      (var-set total-assets (+ (var-get total-assets) balance-diff))
      (var-set total-assets (- (var-get total-assets) (- (get balance pool) new-balance)))
    )
    
    (ok new-balance)
  )
)

;; Submit funding request
(define-public (submit-funding-request (amount uint) (purpose (string-ascii 200)) (urgency (string-ascii 20)))
  (let (
    (request-id (var-get next-funding-id))
  )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-none (map-get? funding-requests request-id)) ERR-FUNDING-REQUEST-EXISTS)
    
    (map-set funding-requests request-id
      {
        requester: tx-sender,
        amount: amount,
        purpose: purpose,
        urgency: urgency,
        status: "pending",
        approved-amount: u0,
        created-at: block-height,
        processed-at: u0,
        processed-by: none
      }
    )
    
    (var-set next-funding-id (+ request-id u1))
    (ok request-id)
  )
)

;; Approve funding request
(define-public (approve-funding-request (request-id uint) (approved-amount uint))
  (let (
    (request (unwrap! (map-get? funding-requests request-id) ERR-FUNDING-REQUEST-NOT-FOUND))
    (current-balance (var-get treasury-balance))
  )
    (asserts! (is-authorized tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status request) "pending") ERR-INVALID-STATUS)
    (asserts! (<= approved-amount (get amount request)) ERR-INVALID-AMOUNT)
    (asserts! (>= current-balance approved-amount) ERR-INSUFFICIENT-BALANCE)
    
    (map-set funding-requests request-id
      (merge request {
        status: "approved",
        approved-amount: approved-amount,
        processed-at: block-height,
        processed-by: (some tx-sender)
      })
    )
    
    ;; Update treasury balance
    (var-set treasury-balance (- current-balance approved-amount))
    (unwrap! (update-emergency-buffer) ERR-INVALID-AMOUNT)
    
    (ok approved-amount)
  )
)

;; Reject funding request
(define-public (reject-funding-request (request-id uint))
  (let (
    (request (unwrap! (map-get? funding-requests request-id) ERR-FUNDING-REQUEST-NOT-FOUND))
  )
    (asserts! (is-authorized tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status request) "pending") ERR-INVALID-STATUS)
    
    (map-set funding-requests request-id
      (merge request {
        status: "rejected",
        processed-at: block-height,
        processed-by: (some tx-sender)
      })
    )
    
    (ok true)
  )
)

;; Add funds to treasury
(define-public (add-treasury-funds (amount uint))
  (begin
    (asserts! (is-authorized tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (var-set total-assets (+ (var-get total-assets) amount))
    (unwrap! (update-emergency-buffer) ERR-INVALID-AMOUNT)
    
    ;; Update liquidity ratio
    (var-set liquidity-ratio 
      (calculate-liquidity-ratio (var-get treasury-balance) (var-get total-assets))
    )
    
    (ok (var-get treasury-balance))
  )
)

;; Withdraw treasury funds
(define-public (withdraw-treasury-funds (amount uint))
  (let (
    (current-balance (var-get treasury-balance))
    (emergency-buffer-amount (var-get emergency-buffer))
    (available-amount (if (> current-balance emergency-buffer-amount)
                        (- current-balance emergency-buffer-amount)
                        u0))
  )
    (asserts! (is-authorized tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= amount available-amount) ERR-INSUFFICIENT-BALANCE)
    
    (var-set treasury-balance (- current-balance amount))
    (var-set total-assets (- (var-get total-assets) amount))
    (unwrap! (update-emergency-buffer) ERR-INVALID-AMOUNT)
    
    ;; Update liquidity ratio
    (var-set liquidity-ratio 
      (calculate-liquidity-ratio (var-get treasury-balance) (var-get total-assets))
    )
    
    (ok amount)
  )
)

;; Emergency fund allocation
(define-public (allocate-emergency-funds (amount uint) (justification (string-ascii 200)))
  (let (
    (current-balance (var-get treasury-balance))
    (emergency-buffer-amount (var-get emergency-buffer))
  )
    (asserts! (is-eq tx-sender (var-get treasury-administrator)) ERR-UNAUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= amount emergency-buffer-amount) ERR-INSUFFICIENT-BALANCE)
    
    (var-set treasury-balance (- current-balance amount))
    (unwrap! (update-emergency-buffer) ERR-INVALID-AMOUNT)
    
    (ok amount)
  )
)

;; Update treasury administrator
(define-public (update-treasury-administrator (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get treasury-administrator)) ERR-UNAUTHORIZED)
    (var-set treasury-administrator new-admin)
    (map-set authorized-signers new-admin true)
    (ok true)
  )
)

;; ========================================
;; READ-ONLY FUNCTIONS
;; ========================================

;; Get treasury balance
(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

;; Get total assets
(define-read-only (get-total-assets)
  (var-get total-assets)
)

;; Get liquidity ratio
(define-read-only (get-liquidity-ratio)
  (var-get liquidity-ratio)
)

;; Get emergency buffer
(define-read-only (get-emergency-buffer)
  (var-get emergency-buffer)
)

;; Get available liquidity (balance minus emergency buffer)
(define-read-only (get-available-liquidity)
  (let (
    (balance (var-get treasury-balance))
    (buffer (var-get emergency-buffer))
  )
    (if (> balance buffer) (- balance buffer) u0)
  )
)

;; Get cash flow forecast by ID
(define-read-only (get-cash-flow-forecast (forecast-id uint))
  (map-get? cash-flow-forecasts forecast-id)
)

;; Get liquidity pool by ID
(define-read-only (get-liquidity-pool (pool-id uint))
  (map-get? liquidity-pools pool-id)
)

;; Get funding request by ID
(define-read-only (get-funding-request (request-id uint))
  (map-get? funding-requests request-id)
)

;; Check if user is authorized
(define-read-only (is-user-authorized (user principal))
  (is-authorized user)
)

;; Get treasury health metrics
(define-read-only (get-treasury-health)
  (let (
    (balance (var-get treasury-balance))
    (assets (var-get total-assets))
    (liabilities (var-get total-liabilities))
    (liquidity (var-get liquidity-ratio))
    (buffer (var-get emergency-buffer))
  )
    {
      treasury-balance: balance,
      total-assets: assets,
      total-liabilities: liabilities,
      net-worth: (- assets liabilities),
      liquidity-ratio: liquidity,
      emergency-buffer: buffer,
      available-liquidity: (if (> balance buffer) (- balance buffer) u0),
      health-score: (if (>= liquidity (* MIN-LIQUIDITY-RATIO u100)) u100 u50)
    }
  )
)

;; Get treasury administrator
(define-read-only (get-treasury-administrator)
  (var-get treasury-administrator)
)
