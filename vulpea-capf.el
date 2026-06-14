;;; vulpea-capf.el --- Completion-at-point for Vulpea nodes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 neonmei

;; Author: neonmei <releng@neonmei.cloud>
;; Maintainer: neonmei <releng@neonmei.cloud>
;; URL: https://github.com/neonmei/vulpea-capf
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (vulpea "2.0"))
;; Keywords: convenience, outlines, org

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; `vulpea-capf' provides `completion-at-point' functions (capfs) that
;; complete the text at point to a link to a Vulpea note, inserting an
;; `id:' link.  It is modelled on `org-roam-complete-everywhere' and
;; `org-roam-complete-link-at-point'.
;;
;; Two independent, individually toggleable capfs are provided:
;;
;;   - `vulpea-capf-complete-everywhere' completes any word at point
;;     (gated by `vulpea-capf-everywhere').
;;   - `vulpea-capf-complete-in-brackets' completes inside [[...]]
;;     (gated by `vulpea-capf-in-brackets').
;;
;; Enable them in a buffer with the `vulpea-capf-mode' minor mode, e.g.:
;;
;;   (add-hook 'org-mode-hook #'vulpea-capf-mode)
;;
;; Being plain capfs, candidates surface through whichever in-buffer
;; completion UI you use -- corfu, company (via `company-capf'), or the
;; built-in `completion-at-point'.  `vulpea-capf' itself depends on none
;; of them.

;;; Code:

(require 'org)
(require 'subr-x)
(require 'vulpea-db-query)
(require 'vulpea-note)
(require 'vulpea-select)

(defgroup vulpea-capf nil
  "Completion-at-point for Vulpea nodes."
  :group 'vulpea
  :prefix "vulpea-capf-")

(defcustom vulpea-capf-everywhere t
  "When non-nil, complete the bare word at point to a Vulpea node link."
  :type 'boolean
  :group 'vulpea-capf)

(defcustom vulpea-capf-in-brackets t
  "When non-nil, complete inside [[...]] to a Vulpea node link."
  :type 'boolean
  :group 'vulpea-capf)

(defcustom vulpea-capf-annotate-function #'vulpea-select-annotate
  "Function returning an annotation string for a `vulpea-note', or nil.
When non-nil, its result is appended (faced with `completions-annotations')
to each completion candidate.  This disambiguates notes that share a title
and adds context.  The default, `vulpea-select-annotate', is what Vulpea
uses in its own selection UI (showing #tags and, for an alias candidate,
its primary title).  Set to nil for bare title/alias candidates.

The annotation affects only the completion candidate; the inserted link
description is always the bare title or alias."
  :type '(choice (const :tag "None" nil) function)
  :group 'vulpea-capf)

(defconst vulpea-capf--bracket-re
  (rx "[["
      (group (zero-or-more
              (or (not (any "[]\\"))
                  (and "\\" (zero-or-more "\\\\") (any "[]"))
                  (and (one-or-more "\\") (not (any "[]"))))))
      "]]")
  "Regexp matching inside link brackets, for the brackets capf.")

(defun vulpea-capf--annotate (note)
  "Return a faced annotation suffix for NOTE, or an empty string.
Controlled by `vulpea-capf-annotate-function'."
  (if vulpea-capf-annotate-function
      (let ((s (funcall vulpea-capf-annotate-function note)))
        (if (string-empty-p s)
            ""
          (propertize s 'face 'completions-annotations)))
    ""))

(defun vulpea-capf--candidates ()
  "Return a hash-table mapping each candidate string to (ID . DESCRIPTION).
Each note contributes its title and one candidate per alias (via
`vulpea-note-expand-aliases'), each suffixed with the annotation from
`vulpea-capf--annotate' so that notes sharing a title stay distinct.
DESCRIPTION is the bare title/alias inserted as the link description."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (note (vulpea-db-query))
      (when (vulpea-note-id note)            ; skip non-note headings
        (dolist (n (vulpea-note-expand-aliases note))
          (when-let* ((desc (vulpea-note-title n)))
            (puthash (concat desc (vulpea-capf--annotate n))
                     (cons (vulpea-note-id n) desc)
                     table)))))
    table))

(defun vulpea-capf--completion (beg end table insert-fn)
  "Return a capf over region BEG..END completing TABLE's keys.
TABLE maps each candidate string to (ID . DESCRIPTION).  INSERT-FN is
called with that id and description after the selected candidate has been
removed from BEG..point; it inserts the replacement."
  (list beg end
        (hash-table-keys table)
        :exit-function
        (lambda (str &rest _)
          (when-let* ((cell (gethash (substring-no-properties str) table)))
            (delete-region beg (point))
            (funcall insert-fn (car cell) (cdr cell))))
        ;; Let Org's (and lower-priority) capfs run when nothing matches.
        :exclusive 'no))

;;;###autoload
(defun vulpea-capf-complete-everywhere ()
  "Complete the word at point to a Vulpea node link.
Intended for `completion-at-point-functions'.  Active when
`vulpea-capf-everywhere' is non-nil.  On selection the typed word is
replaced with an `[[id:...][title]]' link."
  (when (and vulpea-capf-everywhere
             (thing-at-point 'word)
             (not (org-in-src-block-p))
             (not (save-match-data (org-in-regexp org-link-any-re))))
    (let ((bounds (bounds-of-thing-at-point 'word)))
      (vulpea-capf--completion
       (car bounds) (cdr bounds) (vulpea-capf--candidates)
       (lambda (id desc) (insert "[[id:" id "][" desc "]]"))))))

;;;###autoload
(defun vulpea-capf-complete-in-brackets ()
  "Complete inside [[...]] to a Vulpea node link.
Intended for `completion-at-point-functions'.  Active when
`vulpea-capf-in-brackets' is non-nil.  The typed title is replaced with
`id:...][title', keeping the closing brackets."
  (when (and vulpea-capf-in-brackets
             (org-in-regexp vulpea-capf--bracket-re 1))
    (let ((beg (match-beginning 1))
          (end (match-end 1)))
      (when (and (<= beg (point) end)
                 (not (org-in-src-block-p)))
        (vulpea-capf--completion
         beg end (vulpea-capf--candidates)
         (lambda (id desc) (insert "id:" id "][" desc) (forward-char 2)))))))

;;;###autoload
(define-minor-mode vulpea-capf-mode
  "Toggle Vulpea node `completion-at-point' in the current buffer.
When enabled, `vulpea-capf-complete-in-brackets' and
`vulpea-capf-complete-everywhere' are added buffer-locally to
`completion-at-point-functions'."
  :lighter nil
  :group 'vulpea-capf
  (if vulpea-capf-mode
      (progn
        (add-hook 'completion-at-point-functions
                  #'vulpea-capf-complete-in-brackets -90 t)
        (add-hook 'completion-at-point-functions
                  #'vulpea-capf-complete-everywhere -80 t))
    (remove-hook 'completion-at-point-functions
                 #'vulpea-capf-complete-in-brackets t)
    (remove-hook 'completion-at-point-functions
                 #'vulpea-capf-complete-everywhere t)))

(provide 'vulpea-capf)
;;; vulpea-capf.el ends here
