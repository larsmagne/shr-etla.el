;;; shr-etla.el --- Expand acronyms in an eww/shr buffer -*- lexical-binding: t; -*-
;; Copyright (C) 2026 Lars Magne Ingebrigtsen

;; Author: Lars Magne Ingebrigtsen <larsi@gnus.org>

;; shr-etla.el is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published
;; by the Free Software Foundation; either version 2, or (at your
;; option) any later version.

;;; Commentary:

;; This is a tiny library to use an LLM to expand acronyms in an
;; eww/shr buffer.

;; Requirements:  https://github.com/larsmagne/query-assistant.el
;;                API keys for some LLM.

;; Usage: `M-x shr-etla RET' in any eww/shr buffer.

;;; Code:

(require 'cl-lib)
(require 'query-assistant)

(defvar shr-etla-assistant 'claude
  "What assistant to use.")

(defface shr-etla
  '((t :inherit warning))
  "Face for translated abbreviations."
  :version "31.0"
  :group 'utilities)

(defun shr-etla ()
  "Expand any acronyms in the current paragraph."
  (interactive)
  (message "Translating...")
  (let* ((start (save-excursion
		  (or (re-search-backward "^\\s-*$" nil t)
		      (point-min))))
	 (end (save-excursion
		(or (re-search-forward "^\\s-*$" nil t)
		    (point-min))))
	 (string (buffer-substring start end))
	 (result (shr-etla--translate string))
	 (inhibit-read-only t)
	 (window-start (window-start))
	 prefix)
    (goto-char start)
    (forward-line 1)
    (save-restriction
      (narrow-to-region (point) end)
      (cl-loop for (abbr expansion) in result
	       do
	       (while (re-search-forward (concat "\\b" abbr "\\b") nil t)
		 (insert " "
			 (propertize (concat "(" expansion ")")
				     'face 'shr-etla))))
      (goto-char (point-min))
      ;; Save the indentation at the start of the paragraph.  This is
      ;; sloppy, but is correct in most cases.
      (setq prefix
	    (if (looking-at "\\s-+")
		(prog1
		    (match-string 0)
		  ;; Don't have leading whitespace.
		  (replace-match ""))
	      ""))
      ;; Translate all whitespace (including newlines) into a single
      ;; space.
      (while (re-search-forward "\\s-+" nil t)
	(replace-match " " t t))
      (goto-char (point-max))
      (insert "\n")
      (goto-char (point-min))
      ;; Fill the text.
      (let ((shr-indentation 0)
	    (shr-start nil)
	    (shr-internal-width (- (shr--window-width)
				   (string-pixel-width prefix)
				   100)))
	(shr-fill-line))
      ;; Restore the indentation.
      (goto-char (point-min))
      (while (not (eobp))
	(insert prefix)
	(forward-line 1))
      (goto-char (point-min)))
    ;; All this narrowing, point movement and text replacement has
    ;; probably made Emacs move the window around.  So fix that.
    (set-window-start nil window-start)
    (message "Translating...done")))

(defun shr-etla--translate (string)
  "Query the LLM.  Return a list of lists of expansions."
  (json-parse-string 
   (query-assistant
    shr-etla-assistant
    (concat
     "In the following text fragment, expand all abbreviations except the
most common ones (i.e., don't expand \"RAM\" and \"CIA\" and the like).
Return a JSON array of arrays where the first element in each sub-array
is the abbreviation and the second element is the expansion.
The abbreviations aren't necessarily capitalized.
Do not return anything except this JSON array.  If there is nothing to
expand, return an empty array."
     (when-let ((url (plist-get eww-data :url)))
       (concat "\nFor context, the web page this was fetched from is "
	       url))
     "\nHere is the text fragment to expand: \n"
     string))
   :array-type 'list))

(provide 'shr-etla)

;;; shr-etla.el ends here.
