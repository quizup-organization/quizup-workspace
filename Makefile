.PHONY: boostrap

check: ## Vérifie les dépendances requises
	@bash scripts/check.sh

boostrap: check ## Clone et build tous les repos
	@bash scripts/boostrap.sh