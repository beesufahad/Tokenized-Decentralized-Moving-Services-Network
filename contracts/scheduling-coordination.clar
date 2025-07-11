;; Scheduling Coordination Contract
;; Optimizes moving timeline and logistics

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_INVALID_SCHEDULE (err u301))
(define-constant ERR_SCHEDULE_NOT_FOUND (err u302))
(define-constant ERR_TIME_CONFLICT (err u303))
(define-constant ERR_INVALID_STATUS (err u304))

;; Data Variables
(define-data-var schedule-counter uint u0)
(define-data-var booking-counter uint u0)

;; Data Maps
(define-map schedules
  uint
  {
    customer: principal,
    provider: principal,
    move-date: uint,
    start-time: uint,
    estimated-duration: uint,
    origin: (string-ascii 200),
    destination: (string-ascii 200),
    crew-size: uint,
    equipment-needed: (string-ascii 300),
    status: (string-ascii 20),
    priority: uint,
    created-at: uint,
    updated-at: uint
  }
)

(define-map bookings
  uint
  {
    schedule-id: uint,
    customer: principal,
    provider: principal,
    booking-date: uint,
    confirmation-code: (string-ascii 20),
    status: (string-ascii 20),
    notes: (string-ascii 500),
    created-at: uint,
    confirmed-at: (optional uint)
  }
)

(define-map provider-availability
  {provider: principal, date: uint}
  {
    available: bool,
    max-bookings: uint,
    current-bookings: uint,
    time-slots: (list 24 bool)
  }
)

(define-map schedule-conflicts
  uint
  {
    schedule-id: uint,
    conflicting-schedule: uint,
    conflict-type: (string-ascii 50),
    resolution-status: (string-ascii 20),
    created-at: uint,
    resolved-at: (optional uint)
  }
)

(define-map customer-schedules
  principal
  (list 50 uint)
)

(define-map provider-schedules
  principal
  (list 100 uint)
)

;; Public Functions

;; Create a new schedule
(define-public (create-schedule
  (provider principal)
  (move-date uint)
  (start-time uint)
  (estimated-duration uint)
  (origin (string-ascii 200))
  (destination (string-ascii 200))
  (crew-size uint)
  (equipment-needed (string-ascii 300))
  (priority uint)
)
  (let ((schedule-id (+ (var-get schedule-counter) u1)))
    (var-set schedule-counter schedule-id)
    (map-set schedules schedule-id {
      customer: tx-sender,
      provider: provider,
      move-date: move-date,
      start-time: start-time,
      estimated-duration: estimated-duration,
      origin: origin,
      destination: destination,
      crew-size: crew-size,
      equipment-needed: equipment-needed,
      status: "pending",
      priority: priority,
      created-at: block-height,
      updated-at: block-height
    })
    ;; Add to customer schedules
    (let ((customer-sched-list (default-to (list) (map-get? customer-schedules tx-sender))))
      (map-set customer-schedules tx-sender
        (unwrap! (as-max-len? (append customer-sched-list schedule-id) u50) ERR_INVALID_SCHEDULE))
    )
    ;; Add to provider schedules
    (let ((provider-sched-list (default-to (list) (map-get? provider-schedules provider))))
      (map-set provider-schedules provider
        (unwrap! (as-max-len? (append provider-sched-list schedule-id) u100) ERR_INVALID_SCHEDULE))
    )
    (ok schedule-id)
  )
)

;; Set provider availability
(define-public (set-availability
  (date uint)
  (available bool)
  (max-bookings uint)
  (time-slots (list 24 bool))
)
  (begin
    (map-set provider-availability {provider: tx-sender, date: date} {
      available: available,
      max-bookings: max-bookings,
      current-bookings: u0,
      time-slots: time-slots
    })
    (ok true)
  )
)

;; Confirm schedule
(define-public (confirm-schedule (schedule-id uint))
  (let ((schedule (unwrap! (map-get? schedules schedule-id) ERR_SCHEDULE_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get provider schedule)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status schedule) "pending") ERR_INVALID_STATUS)
    ;; Check for conflicts
    (asserts! (is-ok (check-schedule-conflicts schedule-id)) ERR_TIME_CONFLICT)
    (map-set schedules schedule-id (merge schedule {
      status: "confirmed",
      updated-at: block-height
    }))
    ;; Update provider availability
    (let ((availability-key {provider: (get provider schedule), date: (get move-date schedule)})
          (availability (default-to {available: true, max-bookings: u5, current-bookings: u0, time-slots: (list true true true true true true true true true true true true true true true true true true true true true true true true)}
                                   (map-get? provider-availability availability-key))))
      (map-set provider-availability availability-key (merge availability {
        current-bookings: (+ (get current-bookings availability) u1)
      }))
    )
    (ok true)
  )
)

;; Create booking
(define-public (create-booking
  (schedule-id uint)
  (confirmation-code (string-ascii 20))
  (notes (string-ascii 500))
)
  (let ((booking-id (+ (var-get booking-counter) u1))
        (schedule (unwrap! (map-get? schedules schedule-id) ERR_SCHEDULE_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get customer schedule)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status schedule) "confirmed") ERR_INVALID_STATUS)
    (var-set booking-counter booking-id)
    (map-set bookings booking-id {
      schedule-id: schedule-id,
      customer: tx-sender,
      provider: (get provider schedule),
      booking-date: (get move-date schedule),
      confirmation-code: confirmation-code,
      status: "booked",
      notes: notes,
      created-at: block-height,
      confirmed-at: (some block-height)
    })
    (ok booking-id)
  )
)

;; Update schedule status
(define-public (update-schedule-status (schedule-id uint) (new-status (string-ascii 20)))
  (let ((schedule (unwrap! (map-get? schedules schedule-id) ERR_SCHEDULE_NOT_FOUND)))
    (asserts! (or (is-eq tx-sender (get customer schedule)) (is-eq tx-sender (get provider schedule))) ERR_UNAUTHORIZED)
    (map-set schedules schedule-id (merge schedule {
      status: new-status,
      updated-at: block-height
    }))
    (ok true)
  )
)

;; Reschedule
(define-public (reschedule
  (schedule-id uint)
  (new-move-date uint)
  (new-start-time uint)
)
  (let ((schedule (unwrap! (map-get? schedules schedule-id) ERR_SCHEDULE_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get customer schedule)) ERR_UNAUTHORIZED)
    (map-set schedules schedule-id (merge schedule {
      move-date: new-move-date,
      start-time: new-start-time,
      status: "rescheduled",
      updated-at: block-height
    }))
    (ok true)
  )
)

;; Private Functions

(define-private (check-schedule-conflicts (schedule-id uint))
  (ok true) ;; Simplified conflict checking
)

;; Read-only functions

(define-read-only (get-schedule (schedule-id uint))
  (map-get? schedules schedule-id)
)

(define-read-only (get-booking (booking-id uint))
  (map-get? bookings booking-id)
)

(define-read-only (get-provider-availability (provider principal) (date uint))
  (map-get? provider-availability {provider: provider, date: date})
)

(define-read-only (get-customer-schedules (customer principal))
  (map-get? customer-schedules customer)
)

(define-read-only (get-provider-schedules (provider principal))
  (map-get? provider-schedules provider)
)

(define-read-only (get-schedule-counter)
  (var-get schedule-counter)
)

(define-read-only (get-booking-counter)
  (var-get booking-counter)
)
