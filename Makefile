.PHONY: check boostrap start-dev apply-dev exit-dev status-dev

check: ## Vérifie les dépendances requises
	@bash scripts/check.sh

boostrap: check ## Clone et build tous les repos
	@bash scripts/boostrap.sh

start-dev: ## Crée une branche type/scope/feature dans les repos ciblés
	@bash scripts/start-dev.sh \
		$(if $(TYPE),--type "$(TYPE)",) \
		$(if $(SCOPE),--scope "$(SCOPE)",) \
		$(if $(FEATURE),--feature "$(FEATURE)",) \
		$(if $(DESC),--description "$(DESC)",) \
		$(if $(REPOS),--repos "$(REPOS)",) \
		$(if $(ALL),--all,) \
		$(if $(DRY_RUN),--dry-run,)

apply-dev: ## Ajoute/commit/push dans les repos ciblés avec commit auto par repo
	@bash scripts/apply-dev.sh \
		$(if $(TYPE),--type "$(TYPE)",) \
		$(if $(DESC),--description "$(DESC)",) \
		$(if $(REPOS),--repos "$(REPOS)",) \
		$(if $(ALL),--all,) \
		$(if $(DRY_RUN),--dry-run,)

exit-dev: ## Remet les repos cibles sur main et supprime la session locale
	@bash scripts/exit-dev.sh \
		$(if $(REPOS),--repos "$(REPOS)",) \
		$(if $(ALL),--all,) \
		$(if $(DRY_RUN),--dry-run,)

status-dev: ## Affiche la session locale et l'etat git des repos cibles
	@bash scripts/status-dev.sh \
		$(if $(REPOS),--repos "$(REPOS)",) \
		$(if $(ALL),--all,)

