
;; title: compliance-reporting
;; version: 1.0.0
;; summary: Regulatory compliance and reporting contract for treasury management
;; description: Manages regulatory compliance tracking, performance metrics, and report generation

;; ========================================
;; ERROR CODES
;; ========================================

(define-constant ERR-UNAUTHORIZED (err u601))
(define-constant ERR-INVALID-PARAMETERS (err u602))
(define-constant ERR-REPORT-EXISTS (err u603))
(define-constant ERR-REPORT-NOT-FOUND (err u604))
(define-constant ERR-METRIC-EXISTS (err u605))
(define-constant ERR-METRIC-NOT-FOUND (err u606))
(define-constant ERR-AUDIT-ENTRY-EXISTS (err u607))
(define-constant ERR-REGULATORY-LIMIT-EXCEEDED (err u608))
(define-constant ERR-INVALID-STATUS (err u609))
(define-constant ERR-INVALID-JURISDICTION (err u610))

;; ========================================
;; CONSTANTS
;; ========================================

(define-constant CONTRACT-OWNER tx-sender)
(define-constant BASIS-POINTS u10000)
(define-constant PERFORMANCE-THRESHOLD u650) ;; 6.5% in basis points
(define-constant MAX-PENALTY-RATE u500) ;; 5% in basis points
(define-constant COMPLIANCE-SCORE-FACTOR u4) ;; Multiplier for compliance score

;; Compliance status codes
(define-constant STATUS-COMPLIANT "compliant")
(define-constant STATUS-WARNING "warning")
(define-constant STATUS-VIOLATION "violation")
(define-constant STATUS-SEVERE "severe-violation")

;; Report types
(define-constant REPORT-TYPE-REGULATORY "regulatory")
(define-constant REPORT-TYPE-PERFORMANCE "performance")
(define-constant REPORT-TYPE-AUDIT "audit")
(define-constant REPORT-TYPE-BENCHMARK "benchmark")

;; ========================================
;; DATA VARIABLES
;; ========================================

(define-data-var compliance-administrator principal CONTRACT-OWNER)
(define-data-var next-report-id uint u1)
(define-data-var next-metric-id uint u1)
(define-data-var next-audit-id uint u1)
(define-data-var next-kfactor-id uint u1)
(define-data-var overall-compliance-score uint u100) ;; 0-100 score
(define-data-var total-penalties uint u0)
(define-data-var last-reporting-date uint u0)

;; ========================================
;; DATA MAPS
;; ========================================

;; Compliance reports
(define-map compliance-reports
  uint
  {
    report-type: (string-ascii 50),
    title: (string-ascii 100),
    description: (string-ascii 500),
    jurisdiction: (string-ascii 50),
    compliance-score: uint,
    status: (string-ascii 20),
    created-at: uint,
    created-by: principal,
    last-updated: uint,
    reportable-period: (string-ascii 50)
  }
)

;; Performance metrics
(define-map performance-metrics
  uint
  {
    metric-name: (string-ascii 100),
    metric-value: uint,
    target-value: uint,
    performance-ratio: uint,
    comparison-benchmark: (string-ascii 100),
    benchmark-value: uint,
    period-start: uint,
    period-end: uint,
    recorded-at: uint,
    recorded-by: principal
  }
)

;; Regulatory limits
(define-map regulatory-limits
  (string-ascii 100) ;; Limit name/identifier
  {
    limit-value: uint,
    current-value: uint,
    warning-threshold: uint,
    jurisdiction: (string-ascii 50),
    description: (string-ascii 300),
    status: (string-ascii 20),
    last-updated: uint
  }
)

;; Audit logs
(define-map audit-logs
  uint
  {
    action-type: (string-ascii 50),
    description: (string-ascii 500),
    entity-affected: (string-ascii 100),
    performed-by: principal,
    timestamp: uint,
    related-data: (optional (string-ascii 1000)),
    compliance-impact: int
  }
)

;; K-Factors (Key Risk Indicators)
(define-map k-factors
  uint
  {
    name: (string-ascii 100),
    description: (string-ascii 300),
    current-value: uint,
    threshold-value: uint,
    weighting: uint,
    status: (string-ascii 20),
    category: (string-ascii 50),
    last-updated: uint
  }
)

;; Benchmark comparisons
(define-map benchmarks
  (string-ascii 100) ;; Benchmark name
  {
    description: (string-ascii 300),
    benchmark-value: uint,
    our-value: uint,
    performance-delta: int,
    period: (string-ascii 50),
    last-updated: uint
  }
)

;; Authorized compliance officers
(define-map authorized-officers principal bool)

;; ========================================
;; PRIVATE FUNCTIONS
;; ========================================

(define-private (is-authorized-officer (user principal))
  (or 
    (is-eq user (var-get compliance-administrator))
    (default-to false (map-get? authorized-officers user))
  )
)

(define-private (calculate-compliance-score (current uint) (weighting uint) (max-score uint))
  (let (
    (weighted-score (/ (* current weighting) BASIS-POINTS))
  )
    (if (> weighted-score max-score)
      max-score
      weighted-score
    )
  )
)

(define-private (get-compliance-status (score uint))
  (if (>= score u90)
    STATUS-COMPLIANT
    (if (>= score u70)
      STATUS-WARNING
      (if (>= score u40)
        STATUS-VIOLATION
        STATUS-SEVERE
      )
    )
  )
)

(define-private (calculate-penalty (severity uint) (base-amount uint))
  (let (
    (penalty-rate (if (>= severity u90) 
                     u0 
                     (/ (* (- u100 severity) MAX-PENALTY-RATE) u100)))
    (penalty-amount (/ (* base-amount penalty-rate) BASIS-POINTS))
  )
    penalty-amount
  )
)

(define-private (validate-date-range (start-date uint) (end-date uint))
  (< start-date end-date)
)

;; ========================================
;; PUBLIC FUNCTIONS
;; ========================================

;; Initialize compliance framework
(define-public (initialize-compliance-framework)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (map-set authorized-officers CONTRACT-OWNER true)
    (var-set last-reporting-date block-height)
    (ok true)
  )
)

;; Create compliance report
(define-public (create-compliance-report
    (report-type (string-ascii 50))
    (title (string-ascii 100))
    (description (string-ascii 500))
    (jurisdiction (string-ascii 50))
    (compliance-score uint)
    (reportable-period (string-ascii 50))
  )
  (let (
    (report-id (var-get next-report-id))
    (status (get-compliance-status compliance-score))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-UNAUTHORIZED)
    (asserts! (<= compliance-score u100) ERR-INVALID-PARAMETERS)
    (asserts! (is-none (map-get? compliance-reports report-id)) ERR-REPORT-EXISTS)
    
    (map-set compliance-reports report-id
      {
        report-type: report-type,
        title: title,
        description: description,
        jurisdiction: jurisdiction,
        compliance-score: compliance-score,
        status: status,
        created-at: block-height,
        created-by: tx-sender,
        last-updated: block-height,
        reportable-period: reportable-period
      }
    )
    
    ;; Update overall compliance score
    (var-set overall-compliance-score 
      (/ (+ (* (var-get overall-compliance-score) u3) compliance-score) u4)
    )
    
    (var-set next-report-id (+ report-id u1))
    (var-set last-reporting-date block-height)
    
    (ok report-id)
  )
)

;; Record performance metric
(define-public (record-performance-metric
    (metric-name (string-ascii 100))
    (metric-value uint)
    (target-value uint)
    (comparison-benchmark (string-ascii 100))
    (benchmark-value uint)
    (period-start uint)
    (period-end uint)
  )
  (let (
    (metric-id (var-get next-metric-id))
    (performance-ratio (if (> target-value u0)
                         (/ (* metric-value BASIS-POINTS) target-value)
                         u0))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-UNAUTHORIZED)
    (asserts! (validate-date-range period-start period-end) ERR-INVALID-PARAMETERS)
    (asserts! (is-none (map-get? performance-metrics metric-id)) ERR-METRIC-EXISTS)
    
    (map-set performance-metrics metric-id
      {
        metric-name: metric-name,
        metric-value: metric-value,
        target-value: target-value,
        performance-ratio: performance-ratio,
        comparison-benchmark: comparison-benchmark,
        benchmark-value: benchmark-value,
        period-start: period-start,
        period-end: period-end,
        recorded-at: block-height,
        recorded-by: tx-sender
      }
    )
    
    (var-set next-metric-id (+ metric-id u1))
    (ok metric-id)
  )
)

;; Set regulatory limit
(define-public (set-regulatory-limit
    (limit-name (string-ascii 100))
    (limit-value uint)
    (warning-threshold uint)
    (jurisdiction (string-ascii 50))
    (description (string-ascii 300))
  )
  (begin
    (asserts! (is-authorized-officer tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> limit-value u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= warning-threshold limit-value) ERR-INVALID-PARAMETERS)
    
    (map-set regulatory-limits limit-name
      {
        limit-value: limit-value,
        current-value: u0,
        warning-threshold: warning-threshold,
        jurisdiction: jurisdiction,
        description: description,
        status: STATUS-COMPLIANT,
        last-updated: block-height
      }
    )
    
    (ok limit-value)
  )
)

;; Update regulatory limit value
(define-public (update-regulatory-limit-value (limit-name (string-ascii 100)) (current-value uint))
  (let (
    (limit (unwrap! (map-get? regulatory-limits limit-name) ERR-REPORT-NOT-FOUND))
    (limit-value (get limit-value limit))
    (warning-threshold (get warning-threshold limit))
    (status (if (<= current-value warning-threshold)
               STATUS-COMPLIANT
               (if (<= current-value limit-value)
                 STATUS-WARNING
                 STATUS-VIOLATION)))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-UNAUTHORIZED)
    
    ;; If exceeding regulatory limit, calculate penalties
    (if (> current-value limit-value)
      (var-set total-penalties 
        (+ (var-get total-penalties) 
           (calculate-penalty u40 current-value)))
      true
    )
    
    (map-set regulatory-limits limit-name
      (merge limit {
        current-value: current-value,
        status: status,
        last-updated: block-height
      })
    )
    
    (ok status)
  )
)

;; Record audit log entry
(define-public (record-audit-log
    (action-type (string-ascii 50))
    (description (string-ascii 500))
    (entity-affected (string-ascii 100))
    (related-data (optional (string-ascii 1000)))
    (compliance-impact int)
  )
  (let (
    (audit-id (var-get next-audit-id))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? audit-logs audit-id)) ERR-AUDIT-ENTRY-EXISTS)
    
    (map-set audit-logs audit-id
      {
        action-type: action-type,
        description: description,
        entity-affected: entity-affected,
        performed-by: tx-sender,
        timestamp: block-height,
        related-data: related-data,
        compliance-impact: compliance-impact
      }
    )
    
    (var-set next-audit-id (+ audit-id u1))
    (ok audit-id)
  )
)

;; Add K-Factor (Key Risk Indicator)
(define-public (add-k-factor
    (name (string-ascii 100))
    (description (string-ascii 300))
    (current-value uint)
    (threshold-value uint)
    (weighting uint)
    (category (string-ascii 50))
  )
  (let (
    (k-factor-id (var-get next-kfactor-id))
    (status (if (< current-value threshold-value) 
               STATUS-COMPLIANT 
               STATUS-WARNING))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> threshold-value u0) ERR-INVALID-PARAMETERS)
    (asserts! (<= weighting BASIS-POINTS) ERR-INVALID-PARAMETERS)
    
    (map-set k-factors k-factor-id
      {
        name: name,
        description: description,
        current-value: current-value,
        threshold-value: threshold-value,
        weighting: weighting,
        status: status,
        category: category,
        last-updated: block-height
      }
    )
    
    (var-set next-kfactor-id (+ k-factor-id u1))
    (ok k-factor-id)
  )
)

;; Update K-Factor value
(define-public (update-k-factor (k-factor-id uint) (new-value uint))
  (let (
    (k-factor (unwrap! (map-get? k-factors k-factor-id) ERR-METRIC-NOT-FOUND))
    (threshold (get threshold-value k-factor))
    (status (if (< new-value threshold) 
               STATUS-COMPLIANT 
               STATUS-WARNING))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-UNAUTHORIZED)
    
    (map-set k-factors k-factor-id
      (merge k-factor {
        current-value: new-value,
        status: status,
        last-updated: block-height
      })
    )
    
    (ok status)
  )
)

;; Add benchmark comparison
(define-public (add-benchmark
    (name (string-ascii 100))
    (description (string-ascii 300))
    (benchmark-value uint)
    (our-value uint)
    (period (string-ascii 50))
  )
  (let (
    (performance-delta (- (to-int our-value) (to-int benchmark-value)))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> benchmark-value u0) ERR-INVALID-PARAMETERS)
    
    (map-set benchmarks name
      {
        description: description,
        benchmark-value: benchmark-value,
        our-value: our-value,
        performance-delta: performance-delta,
        period: period,
        last-updated: block-height
      }
    )
    
    (ok true)
  )
)

;; Update benchmark comparison
(define-public (update-benchmark (name (string-ascii 100)) (benchmark-value uint) (our-value uint))
  (let (
    (benchmark (unwrap! (map-get? benchmarks name) ERR-METRIC-NOT-FOUND))
    (performance-delta (- (to-int our-value) (to-int benchmark-value)))
  )
    (asserts! (is-authorized-officer tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> benchmark-value u0) ERR-INVALID-PARAMETERS)
    
    (map-set benchmarks name
      (merge benchmark {
        benchmark-value: benchmark-value,
        our-value: our-value,
        performance-delta: performance-delta,
        last-updated: block-height
      })
    )
    
    (ok performance-delta)
  )
)

;; Add authorized compliance officer
(define-public (add-authorized-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get compliance-administrator)) ERR-UNAUTHORIZED)
    (map-set authorized-officers officer true)
    (ok true)
  )
)

;; Remove authorized compliance officer
(define-public (remove-authorized-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get compliance-administrator)) ERR-UNAUTHORIZED)
    (map-delete authorized-officers officer)
    (ok true)
  )
)

;; Update compliance administrator
(define-public (update-compliance-administrator (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get compliance-administrator)) ERR-UNAUTHORIZED)
    (var-set compliance-administrator new-admin)
    (map-set authorized-officers new-admin true)
    (ok true)
  )
)

;; ========================================
;; READ-ONLY FUNCTIONS
;; ========================================

;; Get compliance report by ID
(define-read-only (get-compliance-report (report-id uint))
  (map-get? compliance-reports report-id)
)

;; Get performance metric by ID
(define-read-only (get-performance-metric (metric-id uint))
  (map-get? performance-metrics metric-id)
)

;; Get regulatory limit by name
(define-read-only (get-regulatory-limit (limit-name (string-ascii 100)))
  (map-get? regulatory-limits limit-name)
)

;; Get audit log by ID
(define-read-only (get-audit-log (audit-id uint))
  (map-get? audit-logs audit-id)
)

;; Get K-Factor by ID
(define-read-only (get-k-factor (k-factor-id uint))
  (map-get? k-factors k-factor-id)
)

;; Get benchmark by name
(define-read-only (get-benchmark (name (string-ascii 100)))
  (map-get? benchmarks name)
)

;; Get overall compliance score
(define-read-only (get-overall-compliance-score)
  (var-get overall-compliance-score)
)

;; Get total penalties
(define-read-only (get-total-penalties)
  (var-get total-penalties)
)

;; Get compliance administrator
(define-read-only (get-compliance-administrator)
  (var-get compliance-administrator)
)

;; Check if user is authorized officer
(define-read-only (is-officer-authorized (user principal))
  (is-authorized-officer user)
)

;; Get comprehensive compliance report
(define-read-only (get-comprehensive-report)
  {
    overall-score: (var-get overall-compliance-score),
    compliance-status: (get-compliance-status (var-get overall-compliance-score)),
    total-penalties: (var-get total-penalties),
    last-reporting-date: (var-get last-reporting-date),
    next-report-id: (var-get next-report-id),
    next-metric-id: (var-get next-metric-id),
    next-audit-id: (var-get next-audit-id),
    next-kfactor-id: (var-get next-kfactor-id)
  }
)
