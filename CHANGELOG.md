# Changelog

Toutes les modifications notables de ce projet seront documentees dans ce fichier.

Le format s'inspire de Keep a Changelog et le projet suit Semantic Versioning.

## [Unreleased]

## [0.2.0] - 2026-03-16

### Changed
- Remplacement des contrats locaux dupliques par `OrchivisteKitContracts`.
- Intégration de `OrchivisteKitInterop` pour la lecture/ecriture canonique `ToolRequest/ToolResult`.

### Added
- Activation V1 du mode canonique `muni-metadonnees-cli run --request <file> --result <file>`.
- Pipeline d'enrichissement metadata deterministe (mots-cles, resume, titre suggere).
- Support d'un seed depuis la sortie JSON de MuniAnalyse (`analysis_report_path` ou artifact `report`).
- Export optionnel d'un rapport metadata JSON via `metadata_output_path`.
- Tests unitaires interop/canonique (succes, needs_review, erreurs, artefact rapport).
- Versionnage de `Package.resolved` avec pin OrchivisteKit `0.2.0`.

### Removed
- Placeholder nominal `not_implemented` sur le chemin d'execution canonique.

## [0.1.0] - 2026-03-14

### Added
- Version initiale de normalisation du dépôt.
- README, CONTRIBUTING et licence harmonisés pour publication GitHub.
