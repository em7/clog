(in-package :clog-tools)

(defun project-tree-select (panel item &key method)
  (unless (equal item "")
    (cond ((and (> (length item) 5)
                (equal (subseq item (- (length item) 5)) ".clog"))
            (if (or (eq method :tab)
                 (and (not (eq method :here)) *open-external*))
                (on-new-builder-panel-ext panel :open-file item) ;; need ext for both
                (on-new-builder-panel panel :open-file item)))
          (t
            (if (eq method :emacs)
                (swank:ed-in-emacs item)
                (if (or (eq method :tab)
                     (and (not (eq method :here)) *open-external*))
                    (on-open-file-ext panel :open-file item)
                    (progn
                      (let ((win (on-open-file panel :open-file item)))
                        (when *project-tree-sticky-open*
                          (when win
                            (set-geometry win
                                          :top (menu-bar-height win)
                                          :left *builder-left-panel-size*
                                          :height "" :width ""
                                          :bottom 5 :right 0)
                            (clog-ace:resize (window-param win))
                            (set-on-window-move win (lambda (obj)
                                                      (setf (width obj) (width obj))
                                                      (setf (height obj) (height obj))))))))))))))
(defun update-static-root (app)
  (setf *static-root*
        (merge-pathnames (if (equal (current-project app) "clog")
                             "./static-root/"
                             "./www/")
                         (format nil "~A" (asdf:system-source-directory (current-project app)))))
  (when (static-root-display app)
    (setf (text-value (static-root-display app)) (format nil "static-root: ~A" *static-root*))))

(defun on-project-tree (obj &key project)
  (let ((app (connection-data-item obj "builder-app-data")))
    (when (uiop:directory-exists-p #P"~/common-lisp/")
      (pushnew #P"~/common-lisp/"
               (symbol-value (read-from-string "ql:*local-project-directories*"))
               :test #'equalp))
    (when project
      (setf (current-project app) project))
    (if (project-tree-win app)
        (window-focus (project-tree-win app))
        (let* ((*default-title-class*      *builder-title-class*)
               (*default-border-class*     *builder-border-class*)
               (entry-point "")
               (win         (create-gui-window obj :title "Project Tree"
                                               :width *builder-left-panel-size*
                                               :has-pinner t
                                               :keep-on-top t
                                               :client-movement *client-side-movement*))
               (projects    (create-select (window-content win)))
               (panel       (create-panel (window-content win) :background-color :silver
                                          :style "text-align:center;"
                                          :class "w3-tiny"
                                          :height 27 :top 30 :left 0 :right 0))
               (load-btn    (create-button panel :content "no project" :style "height:27px;width:72px"))
               (load-np     (background-color load-btn))
               (run-btn     (create-button panel :content "run" :style "height:27px;width:67px"))
               (filter-btn  (create-button panel :content "filter" :style "height:27px;width:67px"))
               (asd-btn     (create-button panel :content "asd edit" :style "height:27px;width:67px"))
               (refresh-btn (create-button panel :content "&#8635;" :style "height:27px;width:22px"))
               (tree       (create-panel (window-content win)
                                         :class "w3-small"
                                         :overflow :scroll
                                         :top 60 :bottom 0 :left 0 :right 0)))
          (setf (project-tree-win app) win)
          (set-geometry win :top (menu-bar-height win) :left 0 :height "" :bottom 5 :right "")
          (set-on-click asd-btn (lambda (obj)
                                  (on-show-project obj)))
          (set-on-window-move win (lambda (obj)
                                    (setf (height obj) (height obj))))
          (set-on-window-close win (lambda (obj)
                                     (browser-gc obj)
                                     (setf (project-tree-win app) nil)))
          (setf (positioning projects) :absolute)
          (set-geometry projects :height 27 :width "100%" :top 0 :left 0 :right 0)
          (set-on-click (create-span (window-icon-area win) :content "&larr;&nbsp;" :auto-place :top)
                        (lambda (obj)
                          (declare (ignore obj))
                          (set-geometry win :top (menu-bar-height win) :left 0 :height "" :bottom 5 :right "")))
          (set-on-click filter-btn (lambda (obj)
                                     (declare (ignore obj))
                                     (if (equalp (text-value filter-btn)
                                                 "filter")
                                         (setf (text-value filter-btn) "filter off")
                                         (setf (text-value filter-btn) "filter"))))
          (set-on-click run-btn
            (lambda (obj)
              (let* ((*default-title-class*      *builder-title-class*)
                     (*default-border-class*     *builder-border-class*))
                (update-static-root app)
                (input-dialog obj "Run form:"
                              (lambda (result)
                                (when result
                                  (setf entry-point result)
                                  (setf clog:*clog-debug*
                                        (lambda (event data)
                                          (with-clog-debugger (panel :standard-output (stdout app)
                                                                     :standard-input (stdin app))
                                                              (funcall event data))))
                                  (capture-eval result
                                                :clog-obj        obj
                                                :capture-console nil
                                                :capture-result  nil
                                                :eval-in-package "clog-user")))
                                :default-value entry-point)
                (alert-toast obj "Static Root Set"
                             *static-root* :color-class "w3-yellow" :time-out 3))))
          (labels ((project-tree-dir-select (node dir)
                     (let ((filter (equalp (text-value filter-btn)
                                           "filter")))
                       (dolist (item (sort (uiop:subdirectories dir)
                                           (lambda (a b)
                                             (string-lessp (format nil "~A" a) (format nil "~A" b)))))
                         (unless (and (ppcre:scan *project-tree-dir-filter* (string-downcase (format nil "~A" item)))
                                      filter)
                           (create-clog-tree (tree-root node)
                                             :fill-function (lambda (obj)
                                                              (project-tree-dir-select obj (format nil "~A" item)))
                                             :indent-level (1+ (indent-level node))
                                             :visible nil
                                             :on-context-menu
                                               (lambda (obj)
                                                 (browser-gc obj)
                                                 (let* ((disp (text-value (content obj)))
                                                        (menu (create-panel obj
                                                                            :left (left obj) :top (top obj)
                                                                            :width (width obj)
                                                                            :class *builder-window-desktop-class*
                                                                            :auto-place :top))
                                                        (title (create-div menu :content disp))
                                                        (op    (create-div menu :content "Toggle open" :class *builder-menu-context-item-class*))
                                                        (opd   (create-div menu :content "Open in dir tree" :class *builder-menu-context-item-class*))
                                                        (ops   (create-div menu :content "Open in pseudo shell" :class *builder-menu-context-item-class*))
                                                        (opo   (create-div menu :content "Open in os" :class *builder-menu-context-item-class*))
                                                        (grp   (create-div menu :content "Search directory" :class *builder-menu-context-item-class*)))
                                                   (declare (ignore title op))
                                                   (mapcar (lambda (file-extension)
                                                             (set-on-click (create-div menu :content (getf file-extension :name) :class *builder-menu-context-item-class*)
                                                                           (lambda (obj)
                                                                             (destroy menu)
                                                                             (funcall (getf file-extension :func)
                                                                                      nil item (current-project app)
                                                                                      obj))
                                                                           :cancel-event t))
                                                           *file-extensions*)
                                                   (set-on-click menu (lambda (i)
                                                                        (declare (ignore i))
                                                                        (destroy menu)))
                                                   (set-on-click grp (lambda (i)
                                                                       (declare (ignore i))
                                                                       (on-file-search obj :dir item))
                                                                 :cancel-event t)
                                                   (set-on-click opd (lambda (i)
                                                                       (declare (ignore i))
                                                                       (on-dir-tree obj :dir item))
                                                                 :cancel-event t)
                                                   (set-on-click ops (lambda (i)
                                                                       (declare (ignore i))
                                                                       (on-shell obj :dir item))
                                                                 :cancel-event t)
                                                   (set-on-click opo (lambda (i)
                                                                       (declare (ignore i))
                                                                       (open-file-with-os item))
                                                                 :cancel-event t)
                                                   (set-on-mouse-leave menu (lambda (obj) (destroy obj)))))
                                             :content (first (last (pathname-directory item))))))
                       (dolist (item (sort (uiop:directory-files (directory-namestring dir))
                                           (lambda (a b)
                                             (if (equal (pathname-name a) (pathname-name b))
                                                 (string-lessp (format nil "~A" a)
                                                               (format nil "~A" b))
                                                 (string-lessp (format nil "~A" (pathname-name a))
                                                               (format nil "~A" (pathname-name b)))))))
                         (unless (and (ppcre:scan *project-tree-file-filter* (string-downcase (file-namestring item)))
                                      filter)
                           (create-clog-tree-item (tree-root node)
                                                  :on-context-menu
                                                    (lambda (obj)
                                                      (browser-gc obj)
                                                      (let* ((disp (text-value (content obj)))
                                                             (menu (create-panel obj
                                                                                 :left (left obj) :top (top obj)
                                                                                 :width (width obj)
                                                                                 :class *builder-window-desktop-class*
                                                                                 :auto-place :top))
                                                             (title (create-div menu :content disp))
                                                             (op    (create-div menu :content "Open" :class *builder-menu-context-item-class*))
                                                             (oph   (create-div menu :content "Open this tab" :class *builder-menu-context-item-class*))
                                                             (opt   (create-div menu :content "Open new tab" :class *builder-menu-context-item-class*))
                                                             (ope   (create-div menu :content "Open emacs" :class *builder-menu-context-item-class*))
                                                             (opo   (create-div menu :content "Open os default" :class *builder-menu-context-item-class*))
                                                             (del   (create-div menu :content "Delete" :class *builder-menu-context-item-class*)))
                                                        (declare (ignore title op))
                                                        (mapcar (lambda (file-extension)
                                                                  (set-on-click (create-div menu :content (getf file-extension :name) :class *builder-menu-context-item-class*)
                                                                                (lambda (obj)
                                                                                  (destroy menu)
                                                                                  (funcall (getf file-extension :func)
                                                                                           item nil (current-project app)
                                                                                           obj))
                                                                                :cancel-event t))
                                                                *file-extensions*)
                                                        (set-on-click menu (lambda (i)
                                                                             (declare (ignore i))
                                                                             (destroy menu)))
                                                        (set-on-click oph (lambda (i)
                                                                             (declare (ignore i))
                                                                             (project-tree-select obj (format nil "~A" item) :method :here))
                                                                      :cancel-event t)
                                                        (set-on-click opt (lambda (i)
                                                                             (declare (ignore i))
                                                                             (project-tree-select obj (format nil "~A" item) :method :tab))
                                                                      :cancel-event t)
                                                        (set-on-click ope (lambda (i)
                                                                             (declare (ignore i))
                                                                             (project-tree-select obj (format nil "~A" item) :method :emacs))
                                                                      :cancel-event t)
                                                        (set-on-click opo (lambda (i)
                                                                             (declare (ignore i))
                                                                             (open-file-with-os item))
                                                                      :cancel-event t)
                                                        (set-on-click del (lambda (i)
                                                                            (let* ((*default-title-class*      *builder-title-class*)
                                                                                   (*default-border-class*     *builder-border-class*))
                                                                              (confirm-dialog i (format nil "Delete ~A?" disp)
                                                                                              (lambda (result)
                                                                                                (when result
                                                                                                  (uiop:delete-file-if-exists item)
                                                                                                  (destroy obj))))))
                                                                      :cancel-event t)
                                                        (set-on-mouse-leave menu (lambda (obj) (destroy obj)))))
                                                  :on-click (lambda (obj)
                                                              (project-tree-select obj (format nil "~A" item)))
                                                  :content (file-namestring item))))))
                   (load-proj (sel)
                     (setf (text-value load-btn) "working")
                     (setf (background-color load-btn) :yellow)
                     (handler-case
			 (progn
                           (projects-load (format nil "~A/tools" sel))
                           (update-static-root app))
                       (error ()
                              (projects-load sel)))
                              (setf (text-value load-btn) "loaded")
                              (setf (background-color load-btn) load-np)
                              (window-focus win))
                   (on-change (obj)
                     (declare (ignore obj))
                     (setf (text tree) "")
                     (browser-gc tree)
                     (let* ((sel (value projects)))
                       (setf entry-point "")
                       (cond ((equal sel "")
                               (setf (text-value load-btn) "no project")
                               (setf (advisory-title load-btn) "Choose project in drop down")
                               (setf (background-color load-btn) load-np)
                               (setf (current-project app) nil))
                             (t
                              (setf (text-value load-btn) "working")
                              (setf (background-color load-btn) :yellow)
                              (setf (advisory-title load-btn) "")
                              (let* ((root (quicklisp:where-is-system sel))
                                     (dir  (directory-namestring (uiop:truename* root))))
                                (cond (root
                                        (setf (text-value load-btn) "not loaded")
                                        (setf (advisory-title load-btn) "Click to load")
                                        (setf (background-color load-btn) :tomato)
                                        (setf (current-project app) sel)
                                        (setf (current-project-dir app) root)
                                        (create-clog-tree tree
                                                          :fill-function (lambda (obj)
                                                                           (project-tree-dir-select obj dir))
                                                          :node-html "&#129422;" ; lizard
                                                          :content root
                                                          :on-context-menu
                                                          (lambda (obj)
                                                            (browser-gc obj)
                                                            (let* ((disp sel)
                                                                   (item root)
                                                                   (menu (create-panel obj
                                                                                       :left (left obj) :top (top obj)
                                                                                       :width (width obj)
                                                                                       :class *builder-window-desktop-class*
                                                                                       :auto-place :top))
                                                                   (title (create-div menu :content disp))
                                                                   (op    (create-div menu :content "Toggle open" :class *builder-menu-context-item-class*))
                                                                   (opd   (create-div menu :content "Open in dir tree" :class *builder-menu-context-item-class*))
                                                                   (ops   (create-div menu :content "Open pseudo shell" :class *builder-menu-context-item-class*))
                                                                   (opa   (create-div menu :content "Open in ASDF browser" :class *builder-menu-context-item-class*))
                                                                   (opr   (create-div menu :content "Open REPL" :class *builder-menu-context-item-class*))
                                                                   (opo   (create-div menu :content "Open in os" :class *builder-menu-context-item-class*))
                                                                   (grp   (create-div menu :content "Search directory" :class *builder-menu-context-item-class*)))
                                                              (declare (ignore title op))
                                                              (set-on-click menu (lambda (i)
                                                                                   (declare (ignore i))
                                                                                   (destroy menu)))
                                                              (set-on-click opd (lambda (i)
                                                                                  (declare (ignore i))
                                                                                  (on-dir-tree obj :dir item))
                                                                            :cancel-event t)
                                                              (set-on-click grp (lambda (i)
                                                                                  (declare (ignore i))
                                                                                  (on-file-search obj :dir item))
                                                                            :cancel-event t)
                                                              (set-on-click ops (lambda (i)
                                                                                  (declare (ignore i))
                                                                                  (on-shell obj :dir item))
                                                                            :cancel-event t)
                                                              (set-on-click opa (lambda (i)
                                                                                  (declare (ignore i))
                                                                                  (on-new-asdf-browser obj))
                                                                            :cancel-event t)
                                                              (set-on-click opr (lambda (i)
                                                                                  (declare (ignore i))
                                                                                  (on-repl obj))
                                                                            :cancel-event t)
                                                              (set-on-click opo (lambda (i)
                                                                                  (declare (ignore i))
                                                                                  (open-file-with-os item))
                                                                            :cancel-event t)
                                                              (set-on-mouse-leave menu (lambda (obj) (destroy obj))))))
                                        (let ((already (asdf:already-loaded-systems)))
                                          (if (member sel already :test #'equalp)
                                              (progn
                                                (setf (text-value load-btn) "loaded")
                                                (setf (advisory-title load-btn) "Click to unload")
                                                (setf (background-color load-btn) load-np))
                                              (progn
                                                (setf (text-value load-btn) "not loaded")
                                                (setf (advisory-title load-btn) "Click to load")
                                                (setf (background-color load-btn) :tomato))))
                                        (setf entry-point (format nil "(~A)"
                                                                  (or (asdf/system:component-entry-point (asdf:find-system sel))
                                                                      ""))))
                                      (t
                                        (setf entry-point "")
                                        (setf (current-project app) nil)
                                        (setf (text-value load-btn) "no project")
                                        (setf (advisory-title load-btn) "Choose project in drop down")
                                        (setf (background-color load-btn) :load-np))))))))
                   (fill-projects ()
                     (setf (text projects) "")
                     (dolist (n (sort (quicklisp:list-local-systems) #'string-lessp))
                       (add-select-option projects n n :selected (equalp n (current-project app)))
                       (when (equalp n (current-project app))
                         (on-change (current-project app))))
                     (add-select-option projects "" "Select Project" :selected (not (current-project app)))))
            (set-on-click load-btn (lambda (obj)
                                     (declare (ignore obj))
                                     (cond ((equalp (text-value load-btn) "loaded")
                                             (asdf:clear-system (value projects))
                                             (setf (text-value load-btn) "not loaded")
                                             (setf (advisory-title load-btn) "Click to load")
                                             (setf (background-color load-btn) :tomato))
                                           ((equalp (text-value load-btn) "not loaded")
                                            (setf (advisory-title load-btn) "Click to unload")
                                            (load-proj (value projects))))))
            (set-on-click refresh-btn (lambda (obj)
                                        (declare (ignore obj))
                                        (fill-projects)))
            (fill-projects)
            (set-on-change projects #'on-change))))))
