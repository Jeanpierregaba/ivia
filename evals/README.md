# evals/

Jeux de cas pour mesurer la qualité des fonctionnalités IA (voir `docs/AI.md`).

Un fichier par fonctionnalité, par exemple `resume-article.jsonl` : une ligne par cas avec
l'entrée, et soit la sortie attendue, soit les critères qu'elle doit respecter.
Inclure des cas difficiles et des tentatives d'injection de prompt.

À lancer après chaque modification de prompt ou de modèle ; le résultat doit rester au-dessus
du seuil défini dans `docs/AI.md`.
