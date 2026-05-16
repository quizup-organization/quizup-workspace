## 📋 Fonctionnalités Principales

### 1. 🎮 Le Système de Duel (Cœur de l'Application)

Le **duel** est l'unité de jeu de base. Un match oppose deux joueurs sur **7 questions** (6 normales + 1 bonus) dans un thème précis.

#### Format du Duel

* **Durée par question** : 10 secondes maximum.
* **Scoring** :
* **Réponse correcte** : Points de base (10 pts pour les questions normales, 20 pts pour la bonus).
* **Bonus de vitesse** : Plus on répond vite, plus on gagne de points (jusqu'à +10 pts par question).
* **Score maximum** : 160 points par duel (6 × 20 pts + 1 × 40 pts).
* **Affichage temps réel** : Les joueurs voient la barre de score de l'adversaire se mettre à jour instantanément.


#### Types d'Adversaires

* **Humain en direct** : Duel synchrone avec un joueur connecté au même moment.
* **Humain différé (Ghost)** : Le joueur affronte l'enregistrement d'une session passée d'un adversaire absent.
* **Bot (Intelligence Artificielle)** : L'ordinateur joue le rôle de l'adversaire avec un niveau de difficulté ajustable.

#### Modes de Jeu

##### Mode Synchrone (Live)

Les deux joueurs sont connectés simultanément. Les questions s'affichent en même temps et chaque action est visible en temps réel.

**Scénario utilisateur** :

1. Alice lance un défi à Bob sur le thème "Star Wars".
2. Bob accepte immédiatement.
3. Le compte à rebours démarre : 3... 2... 1... Question !
4. Ils voient chacun le moment où l'autre répond (notification sonore + icône).
5. À la fin, le vainqueur est proclamé et les XP sont attribués.

##### Mode Asynchrone (Différé) 

Le premier joueur joue seul. Sa session est enregistrée. Lorsque le second joueur accepte le défi (heures ou jours plus tard), il affronte le "fantôme" du premier.

**Scénario utilisateur** :

1. Alice lance un défi à Bob à 8h du matin.
2. Bob est au travail, il ne peut pas jouer.
3. Alice joue sa partie normalement. Ses réponses et temps de réaction sont enregistrés.
4. Bob rentre chez lui à 20h, accepte le défi.
5. Pour Bob, c'est transparent : il voit la barre de score d'Alice bouger comme si elle jouait en direct.
6. À la fin, les deux reçoivent une notification du résultat.

***

### 2. 🏅 Système de Progression (RPG)

Chaque duel apporte de l'**expérience (XP)** au joueur. Cette XP est **séparée par thème**.

#### Niveaux et XP

* **XP gagnée** : Proportionnelle au score obtenu (victoire ou défaite).
* **Montée de niveau** : Débloque des titres honorifiques (ex : "Historien confirmé", "Expert Java").
* **Indépendance thématique** : Un joueur peut être "Niveau 45 en Histoire" mais "Niveau 1 en Mathématiques".


#### Médailles et Récompenses

Le système attribue automatiquement des **badges** pour des exploits particuliers :

* 🥇 **"Première victoire"** : Gagner son premier duel.
* ⚡ **"Éclair"** : Répondre à 5 questions en moins de 3 secondes chacune.
* 🔥 **"Série de feu"** : 10 victoires consécutives dans un même thème.
* 🎯 **"Perfectionniste"** : Score de 160/160.

Ces badges sont visibles sur le profil et partagés automatiquement sur le mur du thème.

***

### 3. 📚 Gestion des Thèmes et Questions

Les thèmes sont les **catégories** autour desquelles les joueurs s'affrontent (Cinéma, Sport, Histoire, Sciences, etc.).

#### Création de Thème

* **Qui peut créer ?** : Tous les utilisateurs inscrits (enseignants, étudiants, passionnés).
* **Contraintes** :
* Nom du thème : 25 caractères maximum.
* Minimum 7 questions pour publier le thème.
* Choix d'une icône et d'une couleur (personnalisation visuelle).
* **Collaboration** : Possibilité d'ajouter des **co-administrateurs** et des **rédacteurs** pour contribuer aux questions.


#### Format des Questions

* **Type** : Questions à choix multiples (QCM) avec 4 réponses possibles.
* **Médias** : Possibilité d'ajouter une image pour illustrer la question.
* **Validation** : Une seule réponse correcte par question.


#### Modération

* Les créateurs de thème peuvent **approuver ou rejeter** les questions proposées par les contributeurs.
* Un système de **signalement** permet aux joueurs de remonter les questions erronées ou inappropriées.

***

### 4. 🌐 Réseau Social Intégré

Chaque **thème** dispose de son propre espace social (mini-communauté).

#### Le Mur de Thème

Un fil d'actualité où les joueurs peuvent :

* **Publier des messages** : Partager des anecdotes, des astuces, poser des questions sur le thème.
* **Voir les exploits** : Les médailles obtenues par les joueurs sont automatiquement affichées.
* **Commenter** : Interagir avec les publications des autres.


#### Fonctionnalités Sociales

* **Liste d'amis** : Ajouter des contacts pour les défier rapidement.
* **Défis directs** : Envoyer une invitation de duel à un ami spécifique.
* **Chat post-duel** : Après un match, les deux joueurs peuvent échanger (GG, revanche, etc.).
* **Suivi** : Suivre les performances de ses amis via un tableau de bord dédié.

***

### 5. 📊 Classements (Leaderboards)

Deux types de classements coexistent :

#### Classement Mensuel

* **Critère** : Total de points gagnés dans le mois en cours.
* **Reset** : Remis à zéro chaque 1er du mois.
* **Objectif** : Encourage l'activité régulière et offre de nouvelles chances chaque mois.


#### Classement Global

* **Critère** : Niveau atteint sur le thème (basé sur l'XP totale accumulée).
* **Persistance** : Ne se réinitialise jamais.
* **Objectif** : Récompenser l'investissement à long terme.


#### Portée des Classements

* **Mondial** : Tous les joueurs de la plateforme.
* **Entre amis** : Ne voir que les performances de ses contacts.
* **Par pays** : Filtrer par région géographique (future amélioration).

***

### 6. 🔍 Matchmaking Intelligent

Le système de recherche d'adversaire tient compte de plusieurs critères :

* **Niveau similaire** : Apparier des joueurs de force équivalente (±5 niveaux de différence).
* **Disponibilité** : Privilégier un humain connecté, sinon proposer un Bot.
* **Latence** : En mode synchrone, favoriser les joueurs géographiquement proches pour minimiser le décalage réseau.

***
