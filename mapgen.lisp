(in-package #:mapgen)
(in-readtable :qtools)

(defvar *octave* 5)
;; 0 is just base white noise
;; 1 is for the smoothed out noise
;; and anything else is the actual perlin noise
(defvar *mode* 2)
(defvar *debug-map-generation* NIL)

(defclass generated-map ()
  ((noise-map :initform NIL :accessor noise-map)
   (map-image :initform NIL :accessor map-image)))

(defmethod paint ((genmap generated-map) target)
  (let ((image (map-image genmap)))
    (when image
      (let ((rect (q+:rect image)))
        (q+:draw-image target rect image rect)))))

(defmethod set-size ((genmap generated-map) width height)
  (let ((old-map (noise-map genmap)))
    (unless (and (not *debug-map-generation*)
                 old-map
                 (= width (first (array-dimensions old-map)))
                 (= height (second (array-dimensions old-map))))
      (let ((start (internal-time-millis)))
        (let ((map (case *mode*
                     ;; These are for debugging purposes, see *mode*
                     (0 (gen-whitenoise width height))
                     (1 (gen-smooth-noise (gen-whitenoise width height) *octave*))
                     (T (gen-perlin-noise (gen-whitenoise width height) *octave*)))))
          (setf (noise-map genmap) map))
        (v:log :info :mapgen "Regeneration of the map of mode (~a), octave (~a), and size (~a x ~a) took ~a ms."
               *mode* *octave* width height (- (internal-time-millis) start)))
      (let ((image (q+:make-qimage width height (q+:qimage.format_argb32)))
            (start (internal-time-millis))
            (map (noise-map genmap)))
        (dotimes (x width)
          (dotimes (y height)
            (let ((value (aref map x y)))
              (q+:set-pixel image x y (elt *grays* (floor (* 255 value)))))))
        (v:log :info :mapgen "Redrawing the map of size (~a x ~a) took ~a ms."
               width height (- (internal-time-millis) start))
        (when (map-image genmap)
          (finalize (map-image genmap))
          (setf (map-image genmap) NIL))
        (setf (map-image genmap) image)))))

;; Generators

(defun interpolate (x0 x1 alpha)
  (+ (* x0 (- 1 alpha)) (* alpha x1)))

(defun gen-whitenoise (width height)
  (let ((noise (make-array (list width height) :initial-element 0)))
    (dotimes (x width)
      (dotimes (y height)
        (setf (aref noise x y) (/ (random 10000) 10000))))
    noise))

(defun gen-smooth-noise (base-noise octave)
  (let* ((dimensions (array-dimensions base-noise))
         (width (first dimensions))
         (height (second dimensions))
         (smooth-noise (make-array dimensions :initial-element 0))
         (sample-period (ash 1 octave))
         (sample-freq (/ 1.0 sample-period)))
    (dotimes (x width)
      (let* ((sample-x0 (floor (* (floor (/ x sample-period)) sample-period)))
             (sample-x1 (mod (+ sample-x0 sample-period) width))
             (horiz-blend (* (- x sample-x0) sample-freq)))
        (dotimes (y height)
          (let* ((sample-y0 (floor (* (floor (/ y sample-period)) sample-period)))
                 (sample-y1 (mod (+ sample-y0 sample-period) height))
                 (verti-blend (* (- y sample-y0) sample-freq))
                 (top (interpolate (aref base-noise sample-x0 sample-y0)
                                   (aref base-noise sample-x1 sample-y0)
                                   horiz-blend))
                 (bottom (interpolate (aref base-noise sample-x0 sample-y1)
                                      (aref base-noise sample-x1 sample-y1)
                                      horiz-blend)))
            (setf (aref smooth-noise x y) (interpolate top bottom verti-blend))))))
    smooth-noise))

(defun gen-perlin-noise (base-noise octave-count)
  (let* ((dimensions (array-dimensions base-noise))
         (width (first dimensions))
         (height (second dimensions))
         (smooth-noises (make-array (list octave-count) :initial-element 0))
         (persistence 0.5))
    (dotimes (octave octave-count)
      (setf (aref smooth-noises octave) (gen-smooth-noise base-noise octave)))
    (let ((perlin-noise (make-array dimensions :initial-element 0))
          (amplitude 1.0)
          (total-amplitude 0.0))
      (loop for i from (1- octave-count) downto 0 do
            (let ((octave (elt smooth-noises i)))
              (setf amplitude (* amplitude persistence))
              (incf total-amplitude amplitude)
              (dotimes (x width)
                (dotimes (y height)
                  (incf (aref perlin-noise x y) (* (aref octave x y) amplitude))))))
      (dotimes (x width)
        (dotimes (y height)
          (setf (aref perlin-noise x y) (/ (aref perlin-noise x y) total-amplitude))))
      perlin-noise)))
