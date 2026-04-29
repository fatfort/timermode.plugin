# timerMode install/uninstall against an rMPP running xochitl + xovi.
#
# Ships:
#   - build/timerMode.qmd  (compiled from src/timerMode.qml-diff;
#                           injects two QuickSettings tiles —
#                           stopwatch + timer — into ToggleColumn.qml
#                           and ToggleGrid.qml. Pure QML; no systemd.
#                           Persists state to /home/root/.stopwatch-state
#                           and /home/root/.timer-state.)
#
# Default device is USB (10.11.99.1). Override:
#     make install DEVICE=192.168.1.112    # ferrari WLAN
#     make install DEVICE=192.168.1.115    # porsche WLAN
#
# Targets:
#     compile      compile src/timerMode.qml-diff -> build/timerMode.qmd
#     install      compile + push, back up any pre-existing timerMode.qmd
#                  on first install, restart xochitl, journal-check
#     reinstall    recompile + push, restart, no backup churn
#     restore      restore pre-existing timerMode.qmd from .bak if present,
#                  otherwise drop ours; restart
#     uninstall    drop our installed file (and clear state files);
#                  restart
#     status       list installed qmd extensions and our backup on the device
#     preflight    compile + push + restart + grep journalctl for parse/load
#                  errors. Used by `make install` / `make reinstall`; safe to
#                  invoke on its own.

DEVICE   ?= 10.11.99.1
SSH       = ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$(DEVICE)
SCP       = scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
QMD_DIR   = /home/root/xovi/exthome/qt-resource-rebuilder
EXT_TM    = build/timerMode.qmd
SRC_TM    = src/timerMode.qml-diff

.PHONY: compile install reinstall restore uninstall status preflight

compile: $(EXT_TM)

$(EXT_TM): $(SRC_TM) reference/hashtab bin/compile-qmd.sh
	@bin/compile-qmd.sh $(SRC_TM)

install: compile
	@echo "==> Backing up existing timerMode.qmd if present and not already backed up"
	@$(SSH) 'if [ -f $(QMD_DIR)/timerMode.qmd ] && [ ! -f $(QMD_DIR)/timerMode.qmd.bak ]; then cp $(QMD_DIR)/timerMode.qmd $(QMD_DIR)/timerMode.qmd.bak && echo "    backed up"; else echo "    skipped (already backed up or not present)"; fi'
	@echo "==> Pushing timerMode.qmd"
	@$(SCP) $(EXT_TM) root@$(DEVICE):$(QMD_DIR)/timerMode.qmd
	@echo "==> Restarting xochitl"
	@$(SSH) 'systemctl restart xochitl'
	@echo "==> Sleeping 8s for xochitl to load qmd extensions"
	@sleep 8
	@$(MAKE) --no-print-directory _journal_check
	@echo "==> Done. Open Quick Settings (swipe down from top); the stopwatch + timer tiles appear after the stock tiles."

reinstall: compile
	@$(SCP) $(EXT_TM) root@$(DEVICE):$(QMD_DIR)/timerMode.qmd
	@$(SSH) 'systemctl restart xochitl'
	@sleep 8
	@$(MAKE) --no-print-directory _journal_check
	@echo "==> Reinstalled."

preflight: compile
	@$(SCP) $(EXT_TM) root@$(DEVICE):$(QMD_DIR)/timerMode.qmd
	@$(SSH) 'systemctl restart xochitl'
	@sleep 8
	@$(MAKE) --no-print-directory _journal_check

# Internal: scan the most recent xochitl journal for our load + any qmldiff
# parse/load errors or runtime QML errors mentioning ToggleColumn.qml /
# ToggleGrid.qml. Exits with a non-zero status if a parse error is detected.
.PHONY: _journal_check
_journal_check:
	@echo "==> Journal check (qmldiff load + Toggle{Column,Grid} errors)"
	@$(SSH) "journalctl -u xochitl --since '20 sec ago' --no-pager 2>/dev/null \
	    | grep -iE 'qmldiff.*timerMode|qmldiff.*Failed|qmldiff.*Error|qml.*ToggleColumn|qml.*ToggleGrid' \
	    || echo '    (no matching journal lines — clean)'"
	@$(SSH) "journalctl -u xochitl --since '20 sec ago' --no-pager 2>/dev/null \
	    | grep -iE 'qmldiff.*timerMode.*Error while parsing' \
	    && (echo '    !!! parse error detected — fix and redeploy'; exit 1) \
	    || true"

restore:
	@echo "==> Restoring timerMode.qmd from .bak if present, else removing ours"
	@$(SSH) 'if [ -f $(QMD_DIR)/timerMode.qmd.bak ]; then mv $(QMD_DIR)/timerMode.qmd.bak $(QMD_DIR)/timerMode.qmd && echo "    restored from .bak"; else rm -f $(QMD_DIR)/timerMode.qmd && echo "    no .bak; removed our copy"; fi'
	@$(SSH) 'systemctl restart xochitl'
	@echo "==> Restored."

uninstall:
	@$(SSH) 'rm -f $(QMD_DIR)/timerMode.qmd /home/root/.stopwatch-state /home/root/.timer-state'
	@$(SSH) 'if [ -f $(QMD_DIR)/timerMode.qmd.bak ]; then mv $(QMD_DIR)/timerMode.qmd.bak $(QMD_DIR)/timerMode.qmd && echo "    restored .bak"; fi'
	@$(SSH) 'systemctl restart xochitl'
	@echo "==> Uninstalled."

status:
	@$(SSH) 'echo "===qmd==="; ls -la $(QMD_DIR)/timerMode.qmd $(QMD_DIR)/timerMode.qmd.bak 2>/dev/null || echo "  (not installed)"; \
	         echo "===stopwatch==="; cat /home/root/.stopwatch-state 2>/dev/null || echo "  (no state file)"; \
	         echo "===timer==="; cat /home/root/.timer-state 2>/dev/null || echo "  (no state file)"'
