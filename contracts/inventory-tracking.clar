;; Inventory Tracking Contract
;; Manages household item documentation and protection

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INVALID_ITEM (err u201))
(define-constant ERR_ITEM_NOT_FOUND (err u202))
(define-constant ERR_INVALID_STATUS (err u203))
(define-constant ERR_ALREADY_EXISTS (err u204))

;; Data Variables
(define-data-var item-counter uint u0)
(define-data-var inventory-counter uint u0)

;; Data Maps
(define-map inventories
  uint
  {
    owner: principal,
    move-id: uint,
    title: (string-ascii 100),
    total-items: uint,
    total-value: uint,
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint
  }
)

(define-map inventory-items
  uint
  {
    inventory-id: uint,
    name: (string-ascii 100),
    description: (string-ascii 300),
    category: (string-ascii 50),
    estimated-value: uint,
    condition: (string-ascii 20),
    fragile: bool,
    dimensions: (string-ascii 50),
    weight: uint,
    photo-hash: (string-ascii 64),
    protection-level: (string-ascii 20),
    status: (string-ascii 20),
    created-at: uint,
    updated-at: uint
  }
)

(define-map inventory-items-list
  uint
  (list 100 uint)
)

(define-map item-conditions
  uint
  {
    item-id: uint,
    condition: (string-ascii 20),
    notes: (string-ascii 500),
    inspector: principal,
    inspection-date: uint,
    photos: (list 5 (string-ascii 64))
  }
)

(define-map protection-claims
  uint
  {
    item-id: uint,
    claimant: principal,
    claim-type: (string-ascii 50),
    description: (string-ascii 500),
    claimed-value: uint,
    status: (string-ascii 20),
    created-at: uint,
    resolved-at: (optional uint)
  }
)

;; Public Functions

;; Create a new inventory
(define-public (create-inventory
  (move-id uint)
  (title (string-ascii 100))
)
  (let ((inventory-id (+ (var-get inventory-counter) u1)))
    (var-set inventory-counter inventory-id)
    (map-set inventories inventory-id {
      owner: tx-sender,
      move-id: move-id,
      title: title,
      total-items: u0,
      total-value: u0,
      status: "draft",
      created-at: block-height,
      updated-at: block-height
    })
    (map-set inventory-items-list inventory-id (list))
    (ok inventory-id)
  )
)

;; Add item to inventory
(define-public (add-item
  (inventory-id uint)
  (name (string-ascii 100))
  (description (string-ascii 300))
  (category (string-ascii 50))
  (estimated-value uint)
  (condition (string-ascii 20))
  (fragile bool)
  (dimensions (string-ascii 50))
  (weight uint)
  (photo-hash (string-ascii 64))
  (protection-level (string-ascii 20))
)
  (let ((item-id (+ (var-get item-counter) u1))
        (inventory (unwrap! (map-get? inventories inventory-id) ERR_INVALID_ITEM)))
    (asserts! (is-eq tx-sender (get owner inventory)) ERR_UNAUTHORIZED)
    (var-set item-counter item-id)
    (map-set inventory-items item-id {
      inventory-id: inventory-id,
      name: name,
      description: description,
      category: category,
      estimated-value: estimated-value,
      condition: condition,
      fragile: fragile,
      dimensions: dimensions,
      weight: weight,
      photo-hash: photo-hash,
      protection-level: protection-level,
      status: "documented",
      created-at: block-height,
      updated-at: block-height
    })
    ;; Update inventory totals
    (let ((existing-items (default-to (list) (map-get? inventory-items-list inventory-id))))
      (map-set inventory-items-list inventory-id
        (unwrap! (as-max-len? (append existing-items item-id) u100) ERR_INVALID_ITEM))
    )
    (map-set inventories inventory-id (merge inventory {
      total-items: (+ (get total-items inventory) u1),
      total-value: (+ (get total-value inventory) estimated-value),
      updated-at: block-height
    }))
    (ok item-id)
  )
)

;; Update item condition
(define-public (update-item-condition
  (item-id uint)
  (condition (string-ascii 20))
  (notes (string-ascii 500))
  (photos (list 5 (string-ascii 64)))
)
  (let ((item (unwrap! (map-get? inventory-items item-id) ERR_ITEM_NOT_FOUND))
        (inventory (unwrap! (map-get? inventories (get inventory-id item)) ERR_ITEM_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get owner inventory)) ERR_UNAUTHORIZED)
    (map-set inventory-items item-id (merge item {
      condition: condition,
      updated-at: block-height
    }))
    (map-set item-conditions item-id {
      item-id: item-id,
      condition: condition,
      notes: notes,
      inspector: tx-sender,
      inspection-date: block-height,
      photos: photos
    })
    (ok true)
  )
)

;; Finalize inventory
(define-public (finalize-inventory (inventory-id uint))
  (let ((inventory (unwrap! (map-get? inventories inventory-id) ERR_INVALID_ITEM)))
    (asserts! (is-eq tx-sender (get owner inventory)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status inventory) "draft") ERR_INVALID_STATUS)
    (map-set inventories inventory-id (merge inventory {
      status: "finalized",
      updated-at: block-height
    }))
    (ok true)
  )
)

;; Submit protection claim
(define-public (submit-protection-claim
  (item-id uint)
  (claim-type (string-ascii 50))
  (description (string-ascii 500))
  (claimed-value uint)
)
  (let ((item (unwrap! (map-get? inventory-items item-id) ERR_ITEM_NOT_FOUND))
        (inventory (unwrap! (map-get? inventories (get inventory-id item)) ERR_ITEM_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get owner inventory)) ERR_UNAUTHORIZED)
    (map-set protection-claims item-id {
      item-id: item-id,
      claimant: tx-sender,
      claim-type: claim-type,
      description: description,
      claimed-value: claimed-value,
      status: "submitted",
      created-at: block-height,
      resolved-at: none
    })
    (ok true)
  )
)

;; Update item status
(define-public (update-item-status (item-id uint) (new-status (string-ascii 20)))
  (let ((item (unwrap! (map-get? inventory-items item-id) ERR_ITEM_NOT_FOUND))
        (inventory (unwrap! (map-get? inventories (get inventory-id item)) ERR_ITEM_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get owner inventory)) ERR_UNAUTHORIZED)
    (map-set inventory-items item-id (merge item {
      status: new-status,
      updated-at: block-height
    }))
    (ok true)
  )
)

;; Read-only functions

(define-read-only (get-inventory (inventory-id uint))
  (map-get? inventories inventory-id)
)

(define-read-only (get-inventory-item (item-id uint))
  (map-get? inventory-items item-id)
)

(define-read-only (get-inventory-items (inventory-id uint))
  (map-get? inventory-items-list inventory-id)
)

(define-read-only (get-item-condition (item-id uint))
  (map-get? item-conditions item-id)
)

(define-read-only (get-protection-claim (item-id uint))
  (map-get? protection-claims item-id)
)

(define-read-only (get-item-counter)
  (var-get item-counter)
)

(define-read-only (get-inventory-counter)
  (var-get inventory-counter)
)
