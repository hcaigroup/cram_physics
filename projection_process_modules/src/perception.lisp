;;; Copyright (c) 2011, Lorenz Moesenlechner <moesenle@in.tum.de>
;;; All rights reserved.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;; 
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of the Intelligent Autonomous Systems Group/
;;;       Technische Universitaet Muenchen nor the names of its contributors 
;;;       may be used to endorse or promote products derived from this software 
;;;       without specific prior written permission.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :projection-process-modules)

(defclass perceived-object ()
  ((name :reader object-name :initarg :name)
   (pose :reader object-pose :initarg :pose)
   (designator :reader object-designator :initarg :designator)))

(defmethod desig:designator-pose ((designator desig:object-designator))
  (object-pose (desig:reference designator)))

(defmethod desig:designator-distance ((designator-1 desig:object-designator)
                                      (designator-2 desig:object-designator))
  (cl-transforms:v-dist (cl-transforms:origin (desig:designator-pose designator-1))
                        (cl-transforms:origin (desig:designator-pose designator-2))))

(defun make-object-designator (perceived-object &key parent type)
  (let* ((pose (object-pose perceived-object))
         (designator (desig:make-designator
                      'desig-props:object
                      (desig:update-designator-properties
                       `(,(when type `((desig-props:type ,type)))
                         (at ,pose))
                       (when parent (desig:properties parent)))
                      parent)))
    (setf (slot-value perceived-object 'designator) designator)
    (setf (slot-value designator 'desig:data) perceived-object)
    designator))

(defun find-with-bound-designator (designator)
  (let ((object (object-name (desig:reference designator))))
    (cut:force-ll
     (cut:lazy-mapcar (lambda (bdg)
                        (cram-utilities:with-vars-bound (?pose) bdg
                          (assert (not (cut:is-var ?pose)))
                          (make-object-designator
                           (make-instance 'perceived-object
                             :name (object-name object)
                             :pose ?pose)
                           :parent designator)))
                      (crs:prolog `(and (object ,object)
                                        (visible ?_ ,object)
                                        (object-pose ,object ?pose)))))))

(defun find-with-new-designator (designator)
  (desig:with-desig-props (desig-props:type) designator
    (when desig-props:type
      (cut:force-ll
       (cut:lazy-mapcar (lambda (bdg)
                          (cut:with-vars-bound (?object ?pose) bdg
                            (assert (not (or (cut:is-var ?object) (cut:is-var ?pose))))
                            (make-object-designator
                             (make-instance 'perceived-object
                               :name ?object
                               :pose ?pose)
                             :type desig-props:type)))
                        (crs:prolog `(and
                                      (object ?object)
                                      (object-type ?object ,desig-props:type)
                                      (visible ?object)
                                      (pose ?object ?pose))))))))

(def-process-module projection-perception (input)
  (let ((newest-valid-designator (desig:newest-valid-designator input)))
    (if newest-valid-designator
        (find-with-bound-designator newest-valid-designator)
        (find-with-new-designator input))))