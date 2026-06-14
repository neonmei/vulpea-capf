;;; vulpea-capf-test.el --- Tests for vulpea-capf -*- lexical-binding: t; -*-
;;; Commentary:
;; ERT suite.  `vulpea-db-query' is stubbed; no real database is used.
;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'vulpea-capf)

(defun vulpea-capf-test--notes ()
  "Fixture notes for the stubbed `vulpea-db-query'."
  (list
   (make-vulpea-note :id "id-emacs-sw"   :title "Emacs" :tags '("software"))
   (make-vulpea-note :id "id-emacs-band" :title "Emacs" :tags '("band"))
   (make-vulpea-note :id "id-aws" :title "Amazon Web Services" :aliases '("AWS"))
   (make-vulpea-note :id nil :title "Heading No Id")        ; skipped: no id
   (make-vulpea-note :id "id-empty" :title nil)))           ; skipped: no title

(defmacro vulpea-capf-test--with-db (&rest body)
  "Run BODY with `vulpea-db-query' stubbed to the fixture notes."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'vulpea-db-query)
              (lambda (&optional _p) (vulpea-capf-test--notes))))
     ,@body))

(defun vulpea-capf-test--setup (text)
  "Enable Org mode in the current buffer and insert TEXT; point goes to `|'."
  (delay-mode-hooks (org-mode))
  (let ((pos (string-search "|" text)))
    (insert (string-replace "|" "" text))
    (goto-char (1+ (or pos (1- (point-max)))))))

(defmacro vulpea-capf-test--with-buffer (text &rest body)
  "Eval BODY in a temp Org buffer built from TEXT, with the DB stubbed."
  (declare (indent 1))
  `(vulpea-capf-test--with-db
     (with-temp-buffer
       (vulpea-capf-test--setup ,text)
       ,@body)))

(defun vulpea-capf-test--complete (capf target)
  "Invoke CAPF and finish completion with the candidate equal to TARGET.
Return the resulting buffer string."
  (pcase-let ((`(,beg ,end ,coll . ,plist) (funcall capf)))
    (let ((cand (seq-find (lambda (c) (equal (substring-no-properties c) target))
                          coll)))
      (should cand)
      (goto-char beg)
      (delete-region beg end)
      (insert cand)
      (funcall (plist-get plist :exit-function) cand 'finished)))
  (buffer-string))

;;; --- candidate table -------------------------------------------------

(ert-deftest vulpea-capf-test-candidates-annotated-disambiguates ()
  (vulpea-capf-test--with-db
    (let* ((vulpea-capf-annotate-function #'vulpea-select-annotate)
           (tbl (vulpea-capf--candidates)))
      (should (equal (gethash "Emacs #software" tbl) '("id-emacs-sw" . "Emacs")))
      (should (equal (gethash "Emacs #band" tbl)     '("id-emacs-band" . "Emacs")))
      ;; alias keeps its own description, points at the same note id
      (should (equal (gethash "AWS (Amazon Web Services)" tbl)
                     '("id-aws" . "AWS"))))))

(ert-deftest vulpea-capf-test-candidates-bare-collapse ()
  (vulpea-capf-test--with-db
    (let* ((vulpea-capf-annotate-function nil)
           (tbl (vulpea-capf--candidates)))
      ;; with no annotation the two "Emacs" notes collapse to one key
      (should (gethash "Emacs" tbl))
      (should (= 1 (seq-count (lambda (k) (equal k "Emacs"))
                              (hash-table-keys tbl)))))))

(ert-deftest vulpea-capf-test-candidates-skips-headless-and-titleless ()
  (vulpea-capf-test--with-db
    (let ((tbl (vulpea-capf--candidates)))
      (should-not (gethash "Heading No Id" tbl))
      (should-not (seq-find (lambda (v) (equal (car v) "id-empty"))
                            (hash-table-values tbl))))))

;;; --- everywhere capf -------------------------------------------------

(ert-deftest vulpea-capf-test-everywhere-inserts-disambiguated-link ()
  (vulpea-capf-test--with-buffer "Ema|"
    (should (equal (vulpea-capf-test--complete
                    #'vulpea-capf-complete-everywhere "Emacs #band")
                   "[[id:id-emacs-band][Emacs]]"))))

(ert-deftest vulpea-capf-test-everywhere-alias-keeps-description ()
  (vulpea-capf-test--with-buffer "AWS|"
    (should (equal (vulpea-capf-test--complete
                    #'vulpea-capf-complete-everywhere "AWS (Amazon Web Services)")
                   "[[id:id-aws][AWS]]"))))

(ert-deftest vulpea-capf-test-everywhere-skips-src-block ()
  (vulpea-capf-test--with-buffer "#+begin_src emacs-lisp\nEma|\n#+end_src\n"
    (should-not (vulpea-capf-complete-everywhere))))

(ert-deftest vulpea-capf-test-everywhere-skips-existing-link ()
  (vulpea-capf-test--with-buffer "[[id:x][Ema|]]"
    (should-not (vulpea-capf-complete-everywhere))))

(ert-deftest vulpea-capf-test-everywhere-respects-toggle ()
  (vulpea-capf-test--with-buffer "Ema|"
    (let ((vulpea-capf-everywhere nil))
      (should-not (vulpea-capf-complete-everywhere)))))

;;; --- brackets capf ---------------------------------------------------

(ert-deftest vulpea-capf-test-in-brackets-inserts-link ()
  (vulpea-capf-test--with-buffer "[[Ama|]]"
    (should (equal (vulpea-capf-test--complete
                    #'vulpea-capf-complete-in-brackets "Amazon Web Services")
                   "[[id:id-aws][Amazon Web Services]]"))
    ;; point is left after the closing brackets (the `forward-char 2')
    (should (= (point) (point-max)))))

(ert-deftest vulpea-capf-test-in-brackets-inactive-outside-brackets ()
  (vulpea-capf-test--with-buffer "Ama|"
    (should-not (vulpea-capf-complete-in-brackets))))

;;; --- minor mode ------------------------------------------------------

(ert-deftest vulpea-capf-test-mode-registers-capfs ()
  (with-temp-buffer
    (vulpea-capf-mode 1)
    (should (memq #'vulpea-capf-complete-in-brackets completion-at-point-functions))
    (should (memq #'vulpea-capf-complete-everywhere completion-at-point-functions))
    (vulpea-capf-mode -1)
    (should-not (memq #'vulpea-capf-complete-in-brackets completion-at-point-functions))
    (should-not (memq #'vulpea-capf-complete-everywhere completion-at-point-functions))))

(provide 'vulpea-capf-test)
;;; vulpea-capf-test.el ends here
