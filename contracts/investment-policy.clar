
;; title: investment-policy
;; version: 1.0.0
;; summary: Investment policy management contract for treasury risk and investment oversight
;; description: Manages investment policies, risk assessment, and portfolio allocation strategies

;; ========================================
;; ERROR CODES
;; ========================================

(define-constant ERR-UNAUTHORIZED (err u501))
(define-constant ERR-INVALID-AMOUNT (err u502))
(define-constant ERR-INVALID-RISK-LEVEL (err u503))
(define-constant ERR-POLICY-EXISTS (err u504))
(define-constant ERR-POLICY-NOT-FOUND (err u505))
(define-constant ERR-VEHICLE-EXISTS (err u506))
(define-constant ERR-VEHICLE-NOT-FOUND (err u507))
(define-constant ERR-EXPOSURE-LIMIT-EXCEEDED (err u508))
(define-constant ERR-INVALID-ALLOCATION (err u509))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u510))

;; ========================================
;; CONSTANTS
;; ========================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-RISK-SCORE u100)
(define-constant MAX-EXPOSURE-RATIO u5000) ;; 50% in basis points
(define-constant BASIS-POINTS u10000)
(define-constant MIN-DIVERSIFICATION-RATIO u1000) ;; 10%
(define-constant VAR-CONFIDENCE-LEVEL u95) ;; 95% confidence for VaR

;; Risk levels
(define-constant RISK-LOW u1)
(define-constant RISK-MEDIUM u2)
(define-constant RISK-HIGH u3)
(define-constant RISK-CRITICAL u4)

;; ========================================
;; DATA VARIABLES
;; ========================================

(define-data-var policy-administrator principal CONTRACT-OWNER)
(define-data-var next-policy-id uint u1)
(define-data-var next-vehicle-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var total-portfolio-value uint u0)
(define-data-var maximum-single-exposure uint u0)
(define-data-var current-var uint u0) ;; Value at Risk
(define-data-var portfolio-beta uint u100) ;; Portfolio beta (100 = 1.0)

;; ========================================
;; DATA MAPS
;; ========================================

;; Investment policies
(define-map investment-policies
  uint
  {
    name: (string-ascii 100),
    description: (string-ascii 300),
    max-exposure-ratio: uint,
    min-liquidity-ratio: uint,
    max-risk-score: uint,
    diversification-requirement: uint,
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint,
    created-by: principal
  }
)

;; Investment vehicles
(define-map investment-vehicles
  uint
  {
    name: (string-ascii 100),
    vehicle-type: (string-ascii 50),
    risk-score: uint,
    expected-return: uint,
    liquidity-rating: uint,
    current-allocation: uint,
    max-allocation: uint,
    performance-rating: uint,
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint
  }
)

;; Investment proposals
(define-map investment-proposals
  uint
  {
    proposer: principal,
    vehicle-id: uint,
    proposed-amount: uint,
    rationale: (string-ascii 500),
    risk-assessment: uint,
    expected-roi: uint,
    status: (string-ascii 20),
    approved-amount: uint,
    created-at: uint,
    processed-at: uint,
    processed-by: (optional principal)
  }
)

;; Risk assessments
(define-map risk-assessments
  uint
  {
    vehicle-id: uint,
    var-estimate: uint,
    stress-test-result: uint,
    correlation-score: uint,
    liquidity-risk: uint,
    credit-risk: uint,
    market-risk: uint,
    assessed-at: uint,
    assessed-by: principal
  }
)

;; Policy compliance tracking
(define-map compliance-status
  principal
  {
    last-review-date: uint,
    compliance-score: uint,
    violations: uint,
    status: (string-ascii 20)
  }
)

;; Authorized policy managers
(define-map authorized-managers principal bool)

;; ========================================
;; PRIVATE FUNCTIONS
;; ========================================

(define-private (is-authorized-manager (user principal))
  (or 
    (is-eq user (var-get policy-administrator))
    (default-to false (map-get? authorized-managers user))
  )
)

(define-private (calculate-portfolio-risk (vehicle-risk uint) (allocation uint) (total-value uint))
  (if (is-eq total-value u0)
    u0
    (/ (* vehicle-risk allocation) total-value)
  )
)

(define-private (calculate-var (amount uint) (risk-score uint) (confidence uint))
  (let (
    (risk-factor (/ (* risk-score confidence) BASIS-POINTS))
    (var-amount (/ (* amount risk-factor) u100))
  )
    var-amount
  )
)

(define-private (validate-risk-parameters (risk-score uint) (allocation uint))
  (and
    (<= risk-score MAX-RISK-SCORE)
    (> allocation u0)
    (<= allocation BASIS-POINTS)
  )
)

(define-private (check-diversification-compliance (new-allocation uint) (total-portfolio uint))
  (let (
    (allocation-ratio (/ (* new-allocation BASIS-POINTS) total-portfolio))
  )
    (>= allocation-ratio MIN-DIVERSIFICATION-RATIO)
  )
)

;; ========================================
;; PUBLIC FUNCTIONS
;; ========================================

;; Initialize investment policy framework
(define-public (initialize-policy-framework (max-exposure uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= max-exposure MAX-EXPOSURE-RATIO) ERR-INVALID-AMOUNT)
    
    (var-set maximum-single-exposure max-exposure)
    (map-set authorized-managers CONTRACT-OWNER true)
    
    (ok max-exposure)
  )
)

;; Create investment policy
(define-public (create-investment-policy 
    (name (string-ascii 100)) 
    (description (string-ascii 300))
    (max-exposure-ratio uint)
    (min-liquidity-ratio uint)
    (max-risk-score uint)
    (diversification-requirement uint)
  )
  (let (
    (policy-id (var-get next-policy-id))
  )
    (asserts! (is-authorized-manager tx-sender) ERR-UNAUTHORIZED)
    (asserts! (<= max-exposure-ratio MAX-EXPOSURE-RATIO) ERR-INVALID-AMOUNT)
    (asserts! (<= max-risk-score MAX-RISK-SCORE) ERR-INVALID-RISK-LEVEL)
    (asserts! (is-none (map-get? investment-policies policy-id)) ERR-POLICY-EXISTS)
    
    (map-set investment-policies policy-id
      {
        name: name,
        description: description,
        max-exposure-ratio: max-exposure-ratio,
        min-liquidity-ratio: min-liquidity-ratio,
        max-risk-score: max-risk-score,
        diversification-requirement: diversification-requirement,
        status: "active",
        created-at: block-height,
        updated-at: block-height,
        created-by: tx-sender
      }
    )
    
    (var-set next-policy-id (+ policy-id u1))
    (ok policy-id)
  )
)

;; Add investment vehicle
(define-public (add-investment-vehicle
    (name (string-ascii 100))
    (vehicle-type (string-ascii 50))
    (risk-score uint)
    (expected-return uint)
    (liquidity-rating uint)
    (max-allocation uint)
  )
  (let (
    (vehicle-id (var-get next-vehicle-id))
  )
    (asserts! (is-authorized-manager tx-sender) ERR-UNAUTHORIZED)
    (asserts! (validate-risk-parameters risk-score max-allocation) ERR-INVALID-RISK-LEVEL)
    (asserts! (is-none (map-get? investment-vehicles vehicle-id)) ERR-VEHICLE-EXISTS)
    
    (map-set investment-vehicles vehicle-id
      {
        name: name,
        vehicle-type: vehicle-type,
        risk-score: risk-score,
        expected-return: expected-return,
        liquidity-rating: liquidity-rating,
        current-allocation: u0,
        max-allocation: max-allocation,
        performance-rating: u0,
        status: "active",
        created-at: block-height,
        updated-at: block-height
      }
    )
    
    (var-set next-vehicle-id (+ vehicle-id u1))
    (ok vehicle-id)
  )
)

;; Submit investment proposal
(define-public (submit-investment-proposal
    (vehicle-id uint)
    (proposed-amount uint)
    (rationale (string-ascii 500))
    (expected-roi uint)
  )
  (let (
    (proposal-id (var-get next-proposal-id))
    (vehicle (unwrap! (map-get? investment-vehicles vehicle-id) ERR-VEHICLE-NOT-FOUND))
    (risk-assessment (get risk-score vehicle))
  )
    (asserts! (> proposed-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (is-eq (get status vehicle) "active") ERR-INVALID-ALLOCATION)
    
    (map-set investment-proposals proposal-id
      {
        proposer: tx-sender,
        vehicle-id: vehicle-id,
        proposed-amount: proposed-amount,
        rationale: rationale,
        risk-assessment: risk-assessment,
        expected-roi: expected-roi,
        status: "pending",
        approved-amount: u0,
        created-at: block-height,
        processed-at: u0,
        processed-by: none
      }
    )
    
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

;; Approve investment proposal
(define-public (approve-investment-proposal (proposal-id uint) (approved-amount uint))
  (let (
    (proposal (unwrap! (map-get? investment-proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
    (vehicle-id (get vehicle-id proposal))
    (vehicle (unwrap! (map-get? investment-vehicles vehicle-id) ERR-VEHICLE-NOT-FOUND))
    (current-portfolio (var-get total-portfolio-value))
    (new-allocation (+ (get current-allocation vehicle) approved-amount))
    (exposure-ratio (/ (* approved-amount BASIS-POINTS) current-portfolio))
  )
    (asserts! (is-authorized-manager tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status proposal) "pending") ERR-INVALID-ALLOCATION)
    (asserts! (<= approved-amount (get proposed-amount proposal)) ERR-INVALID-AMOUNT)
    (asserts! (<= new-allocation (get max-allocation vehicle)) ERR-EXPOSURE-LIMIT-EXCEEDED)
    (asserts! (<= exposure-ratio (var-get maximum-single-exposure)) ERR-EXPOSURE-LIMIT-EXCEEDED)
    
    ;; Update proposal
    (map-set investment-proposals proposal-id
      (merge proposal {
        status: "approved",
        approved-amount: approved-amount,
        processed-at: block-height,
        processed-by: (some tx-sender)
      })
    )
    
    ;; Update vehicle allocation
    (map-set investment-vehicles vehicle-id
      (merge vehicle {
        current-allocation: new-allocation,
        updated-at: block-height
      })
    )
    
    ;; Update portfolio value
    (var-set total-portfolio-value (+ current-portfolio approved-amount))
    
    (ok approved-amount)
  )
)

;; Reject investment proposal
(define-public (reject-investment-proposal (proposal-id uint) (reason (string-ascii 200)))
  (let (
    (proposal (unwrap! (map-get? investment-proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
  )
    (asserts! (is-authorized-manager tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status proposal) "pending") ERR-INVALID-ALLOCATION)
    
    (map-set investment-proposals proposal-id
      (merge proposal {
        status: "rejected",
        processed-at: block-height,
        processed-by: (some tx-sender)
      })
    )
    
    (ok true)
  )
)

;; Update investment vehicle performance
(define-public (update-vehicle-performance (vehicle-id uint) (performance-rating uint) (actual-return uint))
  (let (
    (vehicle (unwrap! (map-get? investment-vehicles vehicle-id) ERR-VEHICLE-NOT-FOUND))
  )
    (asserts! (is-authorized-manager tx-sender) ERR-UNAUTHORIZED)
    (asserts! (<= performance-rating u100) ERR-INVALID-AMOUNT)
    
    (map-set investment-vehicles vehicle-id
      (merge vehicle {
        performance-rating: performance-rating,
        expected-return: actual-return,
        updated-at: block-height
      })
    )
    
    (ok performance-rating)
  )
)

;; Perform risk assessment
(define-public (perform-risk-assessment
    (vehicle-id uint)
    (var-estimate uint)
    (stress-test-result uint)
    (correlation-score uint)
  )
  (let (
    (vehicle (unwrap! (map-get? investment-vehicles vehicle-id) ERR-VEHICLE-NOT-FOUND))
    (liquidity-risk (- u100 (get liquidity-rating vehicle)))
    (credit-risk (/ (get risk-score vehicle) u2))
    (market-risk (/ (* stress-test-result correlation-score) u100))
  )
    (asserts! (is-authorized-manager tx-sender) ERR-UNAUTHORIZED)
    (asserts! (<= var-estimate BASIS-POINTS) ERR-INVALID-AMOUNT)
    
    (map-set risk-assessments vehicle-id
      {
        vehicle-id: vehicle-id,
        var-estimate: var-estimate,
        stress-test-result: stress-test-result,
        correlation-score: correlation-score,
        liquidity-risk: liquidity-risk,
        credit-risk: credit-risk,
        market-risk: market-risk,
        assessed-at: block-height,
        assessed-by: tx-sender
      }
    )
    
    ;; Update portfolio VaR
    (var-set current-var var-estimate)
    
    (ok var-estimate)
  )
)

;; Rebalance portfolio allocation
(define-public (rebalance-portfolio (vehicle-id uint) (new-allocation uint))
  (let (
    (vehicle (unwrap! (map-get? investment-vehicles vehicle-id) ERR-VEHICLE-NOT-FOUND))
    (current-allocation (get current-allocation vehicle))
    (portfolio-value (var-get total-portfolio-value))
    (allocation-ratio (/ (* new-allocation BASIS-POINTS) portfolio-value))
  )
    (asserts! (is-authorized-manager tx-sender) ERR-UNAUTHORIZED)
    (asserts! (<= new-allocation (get max-allocation vehicle)) ERR-EXPOSURE-LIMIT-EXCEEDED)
    (asserts! (<= allocation-ratio (var-get maximum-single-exposure)) ERR-EXPOSURE-LIMIT-EXCEEDED)
    
    ;; Update vehicle allocation
    (map-set investment-vehicles vehicle-id
      (merge vehicle {
        current-allocation: new-allocation,
        updated-at: block-height
      })
    )
    
    ;; Update total portfolio value
    (if (> new-allocation current-allocation)
      (var-set total-portfolio-value 
        (+ portfolio-value (- new-allocation current-allocation)))
      (var-set total-portfolio-value 
        (- portfolio-value (- current-allocation new-allocation)))
    )
    
    (ok new-allocation)
  )
)

;; Add authorized manager
(define-public (add-authorized-manager (manager principal))
  (begin
    (asserts! (is-eq tx-sender (var-get policy-administrator)) ERR-UNAUTHORIZED)
    (map-set authorized-managers manager true)
    (ok true)
  )
)

;; Remove authorized manager
(define-public (remove-authorized-manager (manager principal))
  (begin
    (asserts! (is-eq tx-sender (var-get policy-administrator)) ERR-UNAUTHORIZED)
    (map-delete authorized-managers manager)
    (ok true)
  )
)

;; Update policy administrator
(define-public (update-policy-administrator (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get policy-administrator)) ERR-UNAUTHORIZED)
    (var-set policy-administrator new-admin)
    (map-set authorized-managers new-admin true)
    (ok true)
  )
)

;; ========================================
;; READ-ONLY FUNCTIONS
;; ========================================

;; Get investment policy by ID
(define-read-only (get-investment-policy (policy-id uint))
  (map-get? investment-policies policy-id)
)

;; Get investment vehicle by ID
(define-read-only (get-investment-vehicle (vehicle-id uint))
  (map-get? investment-vehicles vehicle-id)
)

;; Get investment proposal by ID
(define-read-only (get-investment-proposal (proposal-id uint))
  (map-get? investment-proposals proposal-id)
)

;; Get risk assessment by vehicle ID
(define-read-only (get-risk-assessment (vehicle-id uint))
  (map-get? risk-assessments vehicle-id)
)

;; Calculate portfolio Value at Risk
(define-read-only (calculate-portfolio-var (amount uint))
  (calculate-var amount (var-get current-var) VAR-CONFIDENCE-LEVEL)
)

;; Get portfolio summary
(define-read-only (get-portfolio-summary)
  {
    total-value: (var-get total-portfolio-value),
    current-var: (var-get current-var),
    portfolio-beta: (var-get portfolio-beta),
    max-single-exposure: (var-get maximum-single-exposure),
    diversification-score: (if (> (var-get total-portfolio-value) u0) u85 u0)
  }
)

;; Check policy compliance for a user
(define-read-only (get-compliance-status (user principal))
  (map-get? compliance-status user)
)

;; Get policy administrator
(define-read-only (get-policy-administrator)
  (var-get policy-administrator)
)

;; Check if user is authorized manager
(define-read-only (is-manager-authorized (user principal))
  (is-authorized-manager user)
)

;; Calculate allocation impact
(define-read-only (calculate-allocation-impact (vehicle-id uint) (amount uint))
  (match (map-get? investment-vehicles vehicle-id)
    vehicle
    (let (
      (portfolio-value (var-get total-portfolio-value))
      (risk-contribution (calculate-portfolio-risk (get risk-score vehicle) amount portfolio-value))
      (allocation-ratio (/ (* amount BASIS-POINTS) portfolio-value))
    )
      (ok {
        risk-contribution: risk-contribution,
        allocation-ratio: allocation-ratio,
        expected-return: (/ (* amount (get expected-return vehicle)) BASIS-POINTS),
        liquidity-impact: (get liquidity-rating vehicle),
        compliance-status: (and 
          (<= allocation-ratio (var-get maximum-single-exposure))
          (check-diversification-compliance amount portfolio-value)
        )
      })
    )
    ERR-VEHICLE-NOT-FOUND
  )
)
