# MuniMetadonnees

MuniMetadonnees est l'outil specialise d'enrichissement metadata documentaire de la suite Orchiviste/Muni.

## Mission

Produire un enrichissement metadata deterministe et exploitable via contrat CLI JSON V1 (mots-cles, resume, titre suggere), sans logique IA non deterministe dans cette phase.

## Positionnement

- Outil autonome executable localement.
- Integrable dans Orchiviste (cockpit/hub) via contrat commun OrchivisteKit.
- Peut reutiliser la sortie JSON de MuniAnalyse comme seed d'enrichissement.

## Version

- Version de release: `0.2.0`
- Tag Git: `v0.2.0`

## Contrat CLI JSON V1

Commande canonique:

```bash
muni-metadonnees-cli run --request /path/request.json --result /path/result.json
```

Entrees V1 supportees:

- `parameters.text` (texte inline)
- `parameters.source_path` (chemin ou `file://` vers un fichier texte)
- `parameters.analysis_report_path` (rapport JSON MuniAnalyse)
- `input_artifacts[]` (`kind=input` pour texte, `kind=report` pour rapport d'analyse)
- `parameters.metadata_output_path` (optionnel) pour exporter un rapport JSON

Parametres optionnels:

- `max_keywords` (1...30, defaut 10)
- `summary_sentence_count` (1...5, defaut 2)

Sorties:

- `ToolResult` canonique dans `--result`
- statut nominal: `succeeded` ou `needs_review`
- statut d'erreur: `failed`

## Build et tests

```bash
swift package resolve
swift build
swift test
```

## Licence

GNU GPL v3.0, voir [LICENSE](LICENSE).
