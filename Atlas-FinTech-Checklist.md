# Atlas FinTech — Checklist des Prochaines Étapes

## 🎯 Contexte
Objectif : combler les gaps SAA-C03 identifiés (D1 partiellement, D2/D3 faibles) en ajoutant HTTPS, S3, CloudFront, SQS, et une stratégie DR — puis documenter et créer les diagrammes finaux.

**Règle de travail établie :**
- Modification d'une ressource existante → mise à jour de la doc de phase existante
- Nouvelle capacité → nouvelle phase, nouveau doc
- Toujours : discuter → déployer → tester → screenshots → documenter (dans cet ordre)

---

## ✅ Déjà fait (hors plan initial, mais nécessaire)
- [x] Domaine réel enregistré via Route 53
- [x] Bug délégation GuardDuty/Security Hub résolu (compte délégué `shared-services`, provider aliasé `aws.delegated` pour les ressources de configuration post-délégation)

---

## 📋 Bloc 1 — HTTPS sur l'ALB (met à jour Phase 4)

**Statut : pas encore commencé — seule la discussion des options a eu lieu, rien déployé.**

- [ ] Discuter en profondeur : TLS termination, où ça se passe, pourquoi
- [ ] Demander le certificat ACM (DNS validation via Route 53)
- [ ] Attendre la validation du certificat (statut ISSUED)
- [ ] Ajouter le listener HTTPS:443 (forward vers target group existant)
- [ ] Convertir le listener HTTP:80 existant en redirect vers 443
- [ ] Ouvrir le port 443 sur `alb_sg`
- [ ] Tester dans le navigateur (padlock, pas d'avertissement)
- [ ] Tester la redirection HTTP → HTTPS
- [ ] Screenshots : cert ACM (statut Issued), les 2 listeners, test navigateur
- [ ] Documenter : section "Update — HTTPS/ACM" dans `Phase-4-Compute.md`

---

## 📋 Bloc 2 — S3 + Storage Classes / Lifecycle (nouvelle Phase 9)

- [ ] Discuter : quel usage pour ce bucket (assets statiques ? origine CloudFront ? les deux ?)
- [ ] Discuter : quelles storage classes, quelle logique de transition
- [ ] Créer le bucket S3
- [ ] Configurer les lifecycle rules (transitions Standard → IA → Glacier, expiration si pertinent)
- [ ] Vérifier via console (règles actives, objets si applicable)
- [ ] Screenshots : bucket, lifecycle rules configurées
- [ ] Documenter : nouveau fichier `Phase-9-Storage.md`

---

## 📋 Bloc 3 — CloudFront (nouvelle Phase 10, ou fusionnée avec Bloc 2)

- [ ] Discuter : origine(s) — ALB seul ? S3 seul ? les deux avec origin routing ?
- [ ] Discuter : le certificat ACM doit être en us-east-1 pour CloudFront (point à anticiper)
- [ ] Créer/dupliquer le cert ACM en us-east-1 si besoin
- [ ] Créer la distribution CloudFront
- [ ] Configurer les cache behaviors
- [ ] Pointer le domaine (Route 53) vers CloudFront au lieu de l'ALB direct
- [ ] Tester l'accès via l'URL CloudFront et/ou le domaine
- [ ] Screenshots : distribution CloudFront, cache behaviors, test de latence/caching
- [ ] Documenter : nouveau fichier `Phase-10-CDN.md`

---

## 📋 Bloc 4 — SQS + Decoupling (nouvelle Phase 11)

- [ ] Discuter : quel scénario métier justifie le découplage (quel producteur, quel consommateur)
- [ ] Discuter : SQS standard vs FIFO, pourquoi
- [ ] Créer la queue SQS (+ DLQ si pertinent)
- [ ] Créer/adapter le producteur (Lambda ou service existant)
- [ ] Créer/adapter le consommateur (Lambda avec trigger SQS)
- [ ] Tester le flux end-to-end (message envoyé → traité)
- [ ] Screenshots : queue SQS, message en transit, logs du consumer
- [ ] Documenter : nouveau fichier `Phase-11-Decoupling.md`

---

## 📋 Bloc 5 — DR Strategy / Pilot Light (nouvelle Phase 12 — le plus gros morceau)

- [ ] Discuter en profondeur : rappel des 4 stratégies DR (Backup&Restore, Pilot Light, Warm Standby, Multi-Site Active-Active) et pourquoi Pilot Light ici
- [ ] Discuter : quelle région secondaire, quel scope minimal répliqué
- [ ] Discuter : Route 53 health checks + failover routing — mécanique exacte
- [ ] Répliquer l'infra minimale dans la région secondaire (VPC, compute réduit)
- [ ] Configurer Route 53 failover routing policy + health checks
- [ ] Simuler une panne région primaire (test du failover)
- [ ] Screenshots : Route 53 failover config, health checks, test de bascule
- [ ] Documenter : nouveau fichier `Phase-12-Disaster-Recovery.md`

---

## 📋 Bloc 6 — Finalisation

- [ ] Relire l'ensemble des nouvelles docs (9 à 12) pour cohérence de style avec les phases 2-8
- [ ] Mettre à jour le README principal du repo (vue d'ensemble globale du projet)
- [ ] Créer les diagrammes finaux dans draw.io :
  - [ ] Diagramme 1 — Organisation/Comptes/OUs
  - [ ] Diagramme 2 — Network + Compute (avec HTTPS, CloudFront)
  - [ ] Diagramme 3 (optionnel) — Sécurité & Observabilité (overlay)
  - [ ] Diagramme 4 (optionnel) — DR / multi-région
- [ ] Push final sur GitHub
- [ ] Relire l'inventaire complet du projet pour la prep exam (mapping D1-D4 mis à jour)

---

## 🗺️ Ordre de traitement recommandé

```
1. HTTPS/ACM  →  2. S3  →  3. CloudFront  →  4. SQS  →  5. DR  →  6. Finalisation
```

Chaque bloc suit strictement : **discuter → déployer → tester → screenshots → documenter** avant de passer au suivant.

---
---

# 📐 Checklist 2 — Diagrammes & Structuration du Rapport Final

## 🎯 Contexte
Une fois les 5 blocs infra (Checklist 1) terminés et documentés individuellement, il reste à construire les diagrammes d'ensemble et structurer/rédiger le rapport final consolidé du projet.

**Statut : rien commencé — dépend de la complétion de la Checklist 1.**

---

## 📋 Étape 1 — Préparation avant diagrammes

- [ ] Relire l'inventaire complet du projet (`Atlas-FinTech-Project-Inventory.md`) une fois à jour avec les 5 nouveaux blocs
- [ ] Décider du découpage final des diagrammes (rappel de la discussion : split par purpose, pas un seul mega-diagramme)
- [ ] Lister précisément ce que chaque diagramme doit montrer (éviter le remplissage a posteriori)

## 📋 Étape 2 — Construction des diagrammes (draw.io)

- [ ] **Diagramme 1 — Organisation/Comptes/OUs** : structure Root → OUs → comptes membres, SCPs cascadées
- [ ] **Diagramme 2 — Network + Compute** : VPC, subnets, ALB (HTTPS), ECS Fargate, CloudFront devant, S3 en origine si pertinent
- [ ] **Diagramme 3 — Sécurité & Observabilité (overlay)** : KMS, CloudTrail, GuardDuty/Security Hub (avec délégation), alarms/SNS
- [ ] **Diagramme 4 — DR / multi-région** : région primaire vs secondaire, Route 53 failover, Pilot Light
- [ ] Export de chaque diagramme en PNG, rangés dans le repo (`docs/diagrams/`)

## 📋 Étape 3 — Structuration du rapport final (avant rédaction)

- [ ] Définir le plan/sommaire du rapport (sections, ordre logique)
- [ ] Décider : un seul document consolidé, ou README principal + liens vers les docs de phase existantes ?
- [ ] Lister quels éléments de chaque phase (2 à 12) doivent apparaître dans le résumé exécutif vs rester en détail dans leur doc propre
- [ ] Décider du format des "lessons learned" consolidées (reprendre les points forts de chaque phase sans dupliquer tout le contenu)

## 📋 Étape 4 — Rédaction du rapport final

- [ ] Rédiger la section vue d'ensemble/architecture globale (s'appuie sur les 4 diagrammes)
- [ ] Rédiger le résumé de chaque phase (renvoi vers le doc détaillé, pas de duplication)
- [ ] Rédiger la section "debugging & lessons learned" consolidée (les bugs marquants : launch_type Fargate, OIDC sub claim, délégation GuardDuty/SecurityHub, etc.)
- [ ] Rédiger la section mapping SAA-C03 (quels domaines/services le projet couvre concrètement)
- [ ] Relecture finale + cohérence de style avec les docs de phase existantes

## 📋 Étape 5 — Publication

- [ ] Mettre à jour le README principal du repo avec le rapport final / résumé exécutif
- [ ] Vérifier que tous les liens vers les diagrammes et docs de phase fonctionnent sur GitHub
- [ ] Push final


