# AGENTS.md — Architecture Hexagonale QuizUp

> Ce document est destiné aux LLMs chargés d'implémenter ou de refactoriser un module QuizUp.
> Il décrit les règles, conventions, et patterns à respecter **sans exception**.
> Le module `quizup-identity` est la référence d'implémentation.

---

## 0. Modules Maven

Le monorepo contient les modules suivants (ordre de dépendance) :

| Module               | Package racine                          | Rôle                                               |
|----------------------|-----------------------------------------|----------------------------------------------------|
| `quizup-common`      | `io.github.quizup.common`               | Types domaine partagés, search, exceptions de base |
| `quizup-axon`        | `io.github.quizup.axon`                 | Starter Axon distribué (RabbitMQ, deadlines, etc.) |
| `quizup-starter`     | `io.github.quizup.microservice`         | Spring Boot Starter : CORS, Swagger, Security, WS… |
| `quizup-theme`       | `io.github.quizup.topic`                | Thèmes (topics) et questions                       |
| `quizup-identity`    | `io.github.quizup.identity`             | Authentification, utilisateurs (référence)         |
| `quizup-social`      | `io.github.quizup.social`               | Amis, demandes d'amitié                            |
| `quizup-profile`     | `io.github.quizup.profile`              | Profils joueurs (WIP)                              |
| `quizup-matchmaking` | `io.github.quizup.matchmaking`          | Lobbies et appariement                             |
| `quizup-challenge`   | `io.github.quizup.challenge`            | Défis entre joueurs                                |
| `quizup-game`        | `io.github.quizup.game`                 | Parties (duels), rounds, scoring                   |
| `quizup-gateway`     | `io.github.quizup.gateway`              | API Gateway Spring Cloud                           |

**Attention** : le module `quizup-theme` utilise le package `topic` (pas `theme`).

**Structure Maven réelle des services** : chaque service `quizup-{service}` est un parent (`packaging` = `pom`) avec 2 sous-modules :
- `quizup-{service}-domain` (contient le package `domain/`)
- `quizup-{service}-infrastructure` (contient `application/` + `infrastructure/` + classe `*ServiceApplication`)

---

## 0b. Règle d'or

```
Les flèches de dépendance pointent TOUJOURS vers l'intérieur :
infrastructure → application → domain

Jamais l'inverse. Jamais de raccourci.
```

> Le module `quizup-identity` est la référence d'implémentation pour les patterns purs.
> Le module `quizup-game` est la référence pour les patterns avancés (sous-agrégats, sagas, event store).

Un fichier dans `domain/` ne doit contenir **aucun import** des packages suivants :

- `org.springframework.*`
- `jakarta.persistence.*`
- `org.axonframework.*` (sauf `@Aggregate`, `@AggregateIdentifier`, `@CommandHandler`, `@EventSourcingHandler`,
  `AggregateLifecycle`)
- `*.infrastructure.*`
- `*.application.*`

---

## 1. Structure des packages

```
services/quizup-{module}/
├── quizup-{module}-domain/src/main/java/io/github/quizup/{module}/
│   └── domain/
│       ├── aggregate/          ← Axon aggregates (write model) + sous-agrégats
│       ├── command/            ← Records de commandes (@TargetAggregateIdentifier)
│       ├── event/              ← Records d'événements
│       ├── exception/          ← Exceptions métier (étendent BaseProblem)
│       ├── model/              ← Types domaine purs (records Java, enums, constantes métier)
│       ├── query/              ← Records de queries Axon
│       └── port/
│           ├── in/             ← Use Cases (interfaces, contrats d'entrée)
│           └── out/            ← Ports sortants (interfaces de persistence, services externes)
│
└── quizup-{module}-infrastructure/src/main/java/io/github/quizup/{module}/
    ├── application/
    │   ├── handler/
    │   │   └── query/          ← @QueryHandler Axon (point d'entrée bus Axon)
    │   ├── projection/         ← @EventHandler (mise à jour du read model)
    │   ├── saga/               ← @Saga Axon (orchestration longue durée)
    │   └── service/            ← Implémentations des ports entrants
    ├── infrastructure/
    │   ├── config/             ← @Configuration Spring, DataSeeder
    │   ├── in/
    │   │   ├── api/            ← @RestController, DTOs request/response, mappers
    │   │   └── web/            ← @Controller Thymeleaf (si applicable)
    │   └── out/
    │       ├── messaging/
    │       │   ├── adapter/    ← Adaptateurs bus événements (ex: EventStoreAdapter)
    │       │   ├── mapper/     ← Conversion GameEvent → GameNotification
    │       │   └── response/   ← DTOs de notification WebSocket
    │       └── persistence/
    │           ├── adapter/    ← Implémentations des ports sortants (JPA)
    │           ├── entity/     ← @Entity JPA (avec @Searchable sur les champs filtrables)
    │           ├── mapper/     ← Conversion Entity ↔ Domain model
    │           └── repository/ ← JpaRepository + JpaSpecificationExecutor
    └── {Module}ServiceApplication.java
```

---

## 2. Domain layer — Règles strictes

### 2.1 Modèles domaine

- Utiliser des **`record`** Java immuables.
- Zéro annotation framework.
- Annoter avec **`@Builder(toBuilder = true)`** (Lombok) pour permettre les copies partielles via `.toBuilder()`.
- Les méthodes métier (ex: `hasPassword()`, `hasLinkedProvider()`) vivent ici.

```java
// ✅ Correct
@Builder(toBuilder = true)
public record Question(
                String questionId,
                String topicId,
                String text,
                Map<QuestionChoice, String> answers,
                QuestionChoice correctAnswer,
                QuestionStatus status,
                String creatorId,
                String updatedBy,
                Instant createdAt,
                Instant updatedAt
        ) {
}

// ❌ Interdit
@Entity // ← JPA dans le domaine
public class User { ...
}
```

### 2.2 Exceptions domaine

Deux patterns coexistent selon la complexité du module. Les deux sont valides.

**Pattern A — classe utilitaire `final` avec classes `static` internes** (recommandé pour les modules avec hiérarchie
d'exceptions riche) :

```java
// XxxProblem.java — classe de base abstraite
public abstract class QuestionProblem extends BaseProblem {
    private final String questionId;

    protected QuestionProblem(String questionId, String type, ProblemCategory category,
                              String title, String detail, Map<String, Object> context) {
        super(type, category, title, detail, mergeContext(context, questionId));
        this.questionId = questionId;
    }
    // constructeurs de commodité...
}

// QuestionProblems.java — conteneur des exceptions concrètes
public final class QuestionProblems {
    private QuestionProblems() {
    }

    public static class QuestionNotFoundProblem extends QuestionProblem {
        public QuestionNotFoundProblem(String questionId) {
            super(questionId, "urn:quizup:question:notFound",
                    ProblemCategory.BUSINESS_RESOURCE_MISSING,
                    "Question not found",
                    "The question " + questionId + " was not found", null);
        }
    }

    public static class NotEnoughApprovedQuestionsProblem extends QuestionProblem {
        public NotEnoughApprovedQuestionsProblem(String topicId, int current, int required) {
            super(topicId, "urn:quizup:question:notEnough",
                    "Not enough approved questions",
                    "Topic requires at least " + required + " approved questions, but only " + current + " exist",
                    Map.of("current", current, "required", required));
        }
    }
}
```

**Pattern B — interface `XxxProblems` avec classes internes** (pattern identity-service) :

```java
public interface UserProblems {
    class UserNotFoundProblem extends UserProblem {
        public UserNotFoundProblem(String userId) {
            super(userId, "urn:quizup:user:notFound",
                    ProblemCategory.BUSINESS_RESOURCE_MISSING,
                    "User not found",
                    "The user " + userId + " was not found", null);
        }
    }
}
```

**Règle commune** :

- Toutes les exceptions héritent de `BaseProblem` (package `common.domain.exception`).
- Utilisent `ProblemCategory` (package `common.domain.exception`).
- Le contexte enrichit toujours l'ID de l'entité concernée (`questionId`, `topicId`, `userId`…).

### 2.3 Ports entrants (`domain/port/in/`)

- Une interface = un cas d'utilisation.
- La méthode **principale** accepte toujours un objet Command ou Query du domaine.
- Des méthodes `default` à paramètres à plat sont autorisées comme **raccourcis de commodité**,
  à condition qu'elles délèguent intégralement à la méthode principale — **aucune logique propre**.
- Des méthodes `default` bloquantes suffixées `AndWait` (`.join()`) sont autorisées pour les appelants
  synchrones (ex: `DataSeeder`).
- Les signatures retournent des types domaine (`User`, `PageResult<User>`, `CompletableFuture<User>`).
- **Jamais** de types infrastructure dans les signatures.

```java
// ✅ Correct — méthode principale + default de commodité + default bloquante
public interface ApproveQuestionUseCase {

    CompletableFuture<String> approve(QuestionCommand.ApproveQuestionCommand command);

    default CompletableFuture<String> approve(String questionId, String requesterId) {
        return approve(new QuestionCommand.ApproveQuestionCommand(questionId, requesterId));
    }

    default void approveAndWait(String questionId, String requesterId) {
        approve(questionId, requesterId).join();
    }
}

// ✅ Correct — objet Query comme argument
public interface GetUserUseCase {
    CompletableFuture<User> getById(UserQuery.GetUserQuery query) throws UserProblems.UserNotFoundProblem;

    default CompletableFuture<User> getById(String id) throws UserProblems.UserNotFoundProblem {
        return getById(new UserQuery.GetUserQuery(id));
    }
}

// ❌ Interdit — méthode principale avec paramètres à plat (sans objet Command/Query)
public interface RegisterUserUseCase {
    CompletableFuture<String> registerWithPassword(String userId, String email, String password);
}
```

**Pourquoi** : les méthodes `default` sont de simples wrappers de construction — elles ne cassent
pas le contrat et offrent une API fluide aux appelants sans dupliquer de logique.

### 2.4 Ports sortants (`domain/port/out/`)

- Une interface par responsabilité.
- Retournent des types domaine, jamais des entités JPA.
- Pour les modules simples, un port unique `XxxRepositoryPort` peut regrouper lecture, écriture et
  comptage. Pour les modules complexes, séparer `XxxReadPort` / `XxxWritePort`.

```java
// ✅ Correct — port unifié (pattern topic/identity)
public interface QuestionRepositoryPort {
    void save(Question question);

    Optional<Question> findById(String questionId);

    int countApprovedByTopicId(String topicId);

    List<Question> findRandomApprovedByTopicId(String topicId, int count);

    PageResult<Question> findAll(SearchCriteria searchCriteria);
}

// ✅ Correct — port dédié encodage mot de passe (évite Spring Security dans le domaine)
public interface PasswordEncoderPort {
    String encode(String rawPassword);
}
```

### 2.5 Aggregates Axon

- Injecter les **ports sortants** dans les `@CommandHandler`, **jamais** `QueryGateway`.
- Axon injecte les beans Spring automatiquement dans les constructeurs `@CommandHandler`.
- Toute la validation métier se fait dans le `@CommandHandler` avant `AggregateLifecycle.apply()`.

```java
// ✅ Correct — ports injectés par Axon, validation avant apply
@CommandHandler
public UserAggregate(UserCommand.RegisterUserWithPasswordCommand command,
                     PasswordEncoderPort passwordEncoderPort,
                     UserRepositoryPort userReadPort) {
    validateEmail(command.userId(), command.email(), userReadPort);
    AggregateLifecycle.apply(
            new UserEvent.UserRegisteredEvent(
                    command.userId(),
                    command.email(),
                    passwordEncoderPort.encode(command.password()),
                    null,
                    Instant.now()
            )
    );
}

// ❌ Interdit — QueryGateway dans le domaine
@CommandHandler
public UserAggregate(RegisterUserWithPasswordCommand command, QueryGateway queryGateway) { ...}
```

### 2.6 Constantes métier (`domain/model/XxxRules`)

Les constantes métier partagées entre aggregate et autres couches domaine sont centralisées dans une
**interface** `XxxRules` dans `domain/model/` :

```java
// ✅ Correct
public interface TopicRules {
    int MIN_QUESTIONS_TO_PUBLISH = 7;
}

public final class GameRules {
    public static final int TOTAL_ROUNDS = 7;
    public static final int POINTS_NORMAL = 10;
    public static final int POINTS_BONUS_QUESTION = 20;
    public static final int MAX_SPEED_BONUS = 10;
    public static final long ROUND_TIMEOUT_SECONDS = 10;
    public static final long GAME_TIMEOUT_HOURS = 24;

    private GameRules() {
    }

    public static int calculateSpeedBonus(long timeTakenSeconds) {
        return (int) Math.max(0, MAX_SPEED_BONUS - timeTakenSeconds);
    }

    public static int getBasePoints(boolean isBonusQuestion) {
        return isBonusQuestion ? POINTS_BONUS_QUESTION : POINTS_NORMAL;
    }
}
```

- `interface` pour les constantes pures (pas de logique), `final class` si des méthodes utilitaires
  de calcul sont nécessaires.
- **Jamais** de constantes métier éparpillées dans les aggregates ou les services.

---

### 2.7 Ports sortants inter-modules (`application/service/`)

Quand un module A a besoin de données d'un module B, il définit un **port sortant propre** dans
`domain/port/out/` avec des types locaux, et l'implémentation dans `application/service/` utilise
`QueryGateway` pour interroger le module B via le bus Axon.

```java
// ✅ Correct — port sortant local dans quizup-game/domain/port/out/
public interface QuestionPort {
    List<GameQuestion> findRandomApprovedByTopicId(String topicId, int count);
}

// ✅ Correct — implémentation dans quizup-game/application/service/
@Service
public class QuestionService implements QuestionPort {
    private final QueryGateway queryGateway;

    @Override
    public List<GameQuestion> findRandomApprovedByTopicId(String topicId, int count) {
        List<Question> questions = queryGateway.query(
                new QuestionQuery.GetRandomApprovedQuestionsQuery(topicId, count),
                ResponseTypes.multipleInstancesOf(Question.class)
        ).join();
        return questions.stream()
                .map(q -> new GameQuestion(q.questionId(), q.text(), q.answers(), q.correctAnswer()))
                .toList();
    }
}
```

**Règles** :

- Le type retourné (`GameQuestion`) est un type **local** au module A — jamais un type importé de B.
- L'implémentation va dans `application/service/`, pas dans `infrastructure/` (QueryGateway est
  autorisé en couche application).
- La classe n'implémente **aucun port entrant** — elle est uniquement un adaptateur sortant inter-module.

---

## 3. Application layer — Règles

### 3.1 Services (`application/service/`)

- Implémentent les ports entrants (`domain/port/in/`).
- Autorisés à connaître `CommandGateway` et `QueryGateway` (couche application uniquement).
- Séparation commandes / queries : `XxxCommandService` et `XxxQueryService`.
- `XxxCommandService` implémente uniquement la méthode principale — les méthodes `default` du port
  sont héritées automatiquement, **ne pas les redéfinir**.

```java
// ✅ Correct
@Service
public class UserCommandService implements RegisterUserUseCase {
    private final CommandGateway commandGateway;

    @Override
    public CompletableFuture<String> registerWithPassword(UserCommand.RegisterUserWithPasswordCommand command) {
        return commandGateway.send(command);
    }
}

// ✅ Correct — QueryService regroupe plusieurs use cases query cohérents
@Service
public class UserQueryService implements GetUserUseCase, FindUserUseCase, SearchUserUseCase {
    private final QueryGateway queryGateway;

    @Override
    public CompletableFuture<User> getById(UserQuery.GetUserQuery query) {
        return queryGateway.query(query, ResponseTypes.instanceOf(User.class));
    }

    @Override
    public CompletableFuture<PageResult<User>> search(UserQuery.UserSearchQuery query) {
        return queryGateway.query(query, PageResponseTypes.pageResultOf(User.class));
    }
}
```

### 3.2 Query Handlers (`application/handler/query/`)

- Annotés `@QueryHandler` d'Axon.
- Délèguent **uniquement** aux ports sortants — aucune logique propre.
- Retournent des **types domaine** (`User`, `PageResult<User>`, `boolean`), pas des DTOs.

```java

@Component
public class UserQueryHandler {
    private final UserRepositoryPort userReadPort;

    @QueryHandler
    public User handle(UserQuery.GetUserQuery query) {
        return userReadPort.findById(query.userId())
                .orElseThrow(() -> new UserProblems.UserNotFoundProblem(query.userId()));
    }

    @QueryHandler
    public PageResult<User> handle(UserQuery.UserSearchQuery query) {
        return userReadPort.findAll(query);
    }
}
```

### 3.3 Projections (`application/projection/`)

- Annotées `@EventHandler`.
- Utilisent le port sortant pour persister — **jamais** le repository directement.
- Pour les mises à jour partielles, utiliser `.toBuilder()` (Lombok) sur le record domaine.
- Annoter la méthode avec `@Transactional`.

```java

@Component
public class QuestionProjection {
    private final QuestionRepositoryPort questionRepositoryPort;

    @EventHandler
    @Transactional
    public void on(QuestionEvent.QuestionApprovedEvent event) {
        questionRepositoryPort.findById(event.questionId())
                .ifPresent(question -> questionRepositoryPort.save(
                        question.toBuilder()
                                .status(QuestionStatus.APPROVED)
                                .updatedBy(event.updatedBy())
                                .updatedAt(event.approvedAt())
                                .build()
                ));
    }
}
```

---

## 4. Sous-agrégats (`domain/aggregate/`)

Les **sous-agrégats** (ou entités enfants d'un aggregate) sont des classes Java ordinaires qui
encapsulent un sous-état de l'aggregate principal. Ils vivent dans `domain/aggregate/` aux côtés
de l'aggregate racine.

### 4.1 Règles de conception

- **Classe Java ordinaire** annotée `@Getter` (Lombok) — **pas** d'annotation Axon.
- Pas de `@Builder` : le constructeur doit imposer un état initial cohérent.
- Contient uniquement l'état et les **transitions simples** (pas d'orchestration, pas d'`apply()`).
- L'aggregate racine les instancie et les stocke dans des `Map<EnumKey, XxxAggregate>`.
- Utiliser des **`EnumMap`** pour indexer les sous-agrégats par un enum — élimine les booléens
  `isPlayer1`/`isPlayer2` et les `if/else` en cascade.
- Les méthodes publiques représentent des **transitions d'état** nommées explicitement
  (`join()`, `startRound()`, `closeRound()`, `recordAnswer()`, `addScore()`…).

```java
// ✅ Correct — sous-agrégat joueur
@Getter
public class GamePlayerAggregate {

    private final GamePlayer player;       // enum (PLAYER_1, PLAYER_2)
    private final String playerId;
    private final GamePlayerType playerType;
    private boolean present;
    private int score;

    public GamePlayerAggregate(GamePlayer player, String playerId, GamePlayerType playerType) {
        this.player = player;
        this.playerId = playerId;
        this.playerType = playerType;
        this.present = false;
        this.score = 0;
    }

    public void join() {
        this.present = true;
    }

    public void addScore(int points) {
        this.score += points;
    }

    public boolean matches(String playerId) {
        return this.playerId.equals(playerId);
    }
}

// ✅ Correct — sous-agrégat round
@Getter
public class GameRoundAggregate {

    private final GameRoundType roundId;
    private final GameQuestion question;
    private GameRoundStatus status;
    private Instant startedAt;
    private final Map<GamePlayer, PlayerAnswer> answers = new EnumMap<>(GamePlayer.class);

    public GameRoundAggregate(GameRoundType roundId, GameQuestion question) {
        this.roundId = roundId;
        this.question = question;
        this.status = GameRoundStatus.CREATED;
    }

    public void startRound() {
        this.status = GameRoundStatus.STARTED;
        this.startedAt = Instant.now();
    }

    public void closeRound() {
        this.status = GameRoundStatus.CLOSED;
    }

    public void recordAnswer(PlayerAnswer answer) {
        this.answers.put(answer.player(), answer);
    }

    public boolean hasPlayerAnswered(GamePlayer gamePlayer) {
        return answers.containsKey(gamePlayer);
    }
}
```

### 4.2 Utilisation dans l'aggregate racine

```java

@Aggregate
public class GameAggregate {

    private final Map<GamePlayer, GamePlayerAggregate> players = new EnumMap<>(GamePlayer.class);
    private final Map<GameRoundType, GameRoundAggregate> rounds = new EnumMap<>(GameRoundType.class);

    @EventSourcingHandler
    public void on(GameEvent.GameCreatedEvent event) {
        // Initialisation des sous-agrégats
        players.put(GamePlayer.PLAYER_1, new GamePlayerAggregate(GamePlayer.PLAYER_1, event.player1Id(), GamePlayerType.HUMAN));
        players.put(GamePlayer.PLAYER_2, new GamePlayerAggregate(GamePlayer.PLAYER_2, event.player2Id(), event.player2Type()));

        GameRoundType[] allRounds = GameRoundType.values();
        List<GameQuestion> questions = event.questions();
        for (int i = 0; i < questions.size(); i++) {
            rounds.put(allRounds[i], new GameRoundAggregate(allRounds[i], questions.get(i)));
        }
    }

    // Résolution par identifiant — élimine les if/else
    private GamePlayerAggregate resolvePlayer(String playerId) {
        return players.values().stream()
                .filter(p -> p.matches(playerId))
                .findFirst()
                .orElseThrow(() -> new GameExceptions.PlayerNotInGameProblem(gameId, playerId));
    }
}
```

### 4.3 Ce que les sous-agrégats ne font PAS

| Interdit                                          | Raison                                      |
|---------------------------------------------------|---------------------------------------------|
| `AggregateLifecycle.apply()`                      | Seul l'aggregate racine émet des événements |
| Annotation Axon (`@CommandHandler`, `@Aggregate`) | Ce sont des POJO, pas des aggregates Axon   |
| Logique d'orchestration (appel de Saga, Gateway)  | Responsabilité de la couche application     |
| Être persistés directement via JPA                | La projection est gérée par `XxxProjection` |

---

## 5. Sagas et Deadlines Axon (`application/saga/`)

Les **Sagas** orchestrent des flux longs et multi-étapes déclenchés par des événements. Elles
remplacent toute logique séquentielle qui s'étalerait sur plusieurs transactions ou aggregates.

### 5.1 Règles de structure

- Annotées `@Saga` (Axon).
- Les beans Spring injectés sont déclarés **`transient`** + `@Autowired` — Axon sérialise la saga,
  les beans ne doivent pas l'être.
- Tous les champs d'état sont annotés `@Getter @Setter` (Lombok) — Axon les sérialise/désérialise.
- `SagaLifecycle.end()` pour terminer la saga prématurément (ex: mauvaise branche de démarrage).
- `@StartSaga` marque le premier `@SagaEventHandler`.
- `@EndSaga` marque les `@SagaEventHandler` terminaux.
- L'`associationProperty` correspond toujours à la propriété de corrélation de l'événement
  (ex: `gameId`).

```java

@Saga
public class SyncBotGameSaga {

    @Autowired
    private transient CommandGateway commandGateway;  // ← transient obligatoire

    @Autowired
    private transient DeadlineManager deadlineManager;

    @Getter
    @Setter
    private String gameId;
    @Getter
    @Setter
    private String player1Id;
    @Getter
    @Setter
    private boolean player1Answered;

    @StartSaga
    @SagaEventHandler(associationProperty = "gameId")
    public void on(GameEvent.GameCreatedEvent event) {
        // Terminer immédiatement si la saga ne s'applique pas
        if (!GameMode.SYNC.equals(event.mode())) {
            SagaLifecycle.end();
            return;
        }
        this.gameId = event.gameId();
        commandGateway.send(new GameCommand.JoinGameCommand(gameId, BOT_USER_ID));
    }

    @EndSaga
    @SagaEventHandler(associationProperty = "gameId")
    public void on(GameEvent.GameEndedEvent event) {
        cancelAll();
    }

    @EndSaga
    @SagaEventHandler(associationProperty = "gameId")
    public void on(GameEvent.GameCancelledEvent event) {
        cancelAll();
    }
}
```

### 5.2 Deadlines

Les deadlines permettent de déclencher des actions après un délai. Leur nom et leurs durées sont
centralisés dans une **interface** `XxxDeadline` dans `domain/model/`.

```java
// ✅ Correct — interface de constantes dans domain/model/
public interface GameDeadline {
    String ROUND_EXPIRED = "round-expired";
    Duration ROUND_EXPIRED_TIMEOUT = Duration.ofSeconds(GameRules.ROUND_TIMEOUT_SECONDS);

    String NEXT_ROUND_STARTS = "next-round-starts";
    Duration NEXT_ROUND_STARTS_TIMEOUT = Duration.ofSeconds(3);

    String GAME_EXPIRED = "game-expired";
    Duration GAME_EXPIRED_TIMEOUT = Duration.ofHours(GameRules.GAME_TIMEOUT_HOURS);
}
```

Gestion dans la saga :

```java
// Planifier
String deadlineId = deadlineManager.schedule(
                GameDeadline.ROUND_EXPIRED_TIMEOUT,
                GameDeadline.ROUND_EXPIRED
        );

// Annuler (toujours vérifier nullité avant)
private void cancelRoundDeadline() {
    if (roundDeadlineId != null) {
        deadlineManager.cancelSchedule(GameDeadline.ROUND_EXPIRED, roundDeadlineId);
        roundDeadlineId = null;
    }
}

// Handler de deadline
@DeadlineHandler(deadlineName = GameDeadline.ROUND_EXPIRED)
public void onRoundExpired() {
    // action compensatoire
}
```

**Règles deadlines** :

| Règle                                                            | Raison                                  |
|------------------------------------------------------------------|-----------------------------------------|
| Toujours stocker le `deadlineId` retourné par `schedule()`       | Nécessaire pour annuler précisément     |
| Toujours appeler `cancelSchedule()` dans les handlers `@EndSaga` | Évite des déclenchements orphelins      |
| Vérifier la nullité du `deadlineId` avant annulation             | La saga peut se terminer sans planifier |
| Regrouper les annulations dans une méthode `cancelAll()` privée  | DRY, appelée par tous les `@EndSaga`    |
| Noms de deadline = constantes `String` dans `XxxDeadline`        | Évite les chaînes littérales dispersées |

### 5.3 Ce que les Sagas ne font PAS

| Interdit                                   | Raison                                                       |
|--------------------------------------------|--------------------------------------------------------------|
| Logique de calcul métier (points, scoring) | Appartient aux aggregates                                    |
| Accès direct à la base de données          | Passer par des queries ou ports entrants                     |
| Injection de beans non-`transient`         | Axon sérialise la saga — les beans ne sont pas sérialisables |
| `@Transactional` sur les handlers          | Axon gère ses propres transactions                           |

---

## 6. Notifications WebSocket (`infrastructure/out/messaging/`)

Les notifications temps réel suivent un pattern fixe en trois classes.

### 6.1 Interface `XxxNotification` (`infrastructure/out/messaging/response/`)

- Interface polymorphe décrivant tous les types de notifications d'un module.
- Annotée `@JsonTypeInfo` et `@JsonSubTypes` pour la sérialisation JSON discriminée.
- Chaque sous-type est un `record` qui implémente l'interface et retourne son `type` via
  la méthode `type()`.
- La propriété discriminante JSON est toujours `"type"`.

```java

@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type")
@JsonSubTypes({
        @JsonSubTypes.Type(value = GameNotification.GameCreatedNotification.class, name = "GAME_CREATED"),
        @JsonSubTypes.Type(value = GameNotification.GameEndedNotification.class, name = "GAME_ENDED"),
        // ...
})
public interface GameNotification {

    GameNotificationType type();

    String gameId();

    enum GameNotificationType {
        GAME_CREATED, GAME_STARTED, ROUND_STARTED, PLAYER_ANSWERED,
        ROUND_CLOSED, GAME_ENDED, GAME_CANCELLED, PLAYER_JOINED
    }

    record GameCreatedNotification(
            String gameId,
            String topicId,
            String player1Id,
            String player2Id
    ) implements GameNotification {
        @Override
        public GameNotificationType type() {
            return GameNotificationType.GAME_CREATED;
        }
    }

    record GameEndedNotification(
            String gameId,
            String winnerId,
            int player1FinalScore,
            int player2FinalScore
    ) implements GameNotification {
        @Override
        public GameNotificationType type() {
            return GameNotificationType.GAME_ENDED;
        }
    }
}
```

**Règles** :

- Un seul `enum` interne `XxxNotificationType` liste toutes les valeurs discriminantes.
- Chaque `record` interne expose **uniquement** les données nécessaires au client — pas un copié-collé
  de l'événement domaine.
- Le champ identifiant de ressource (ex: `gameId()`, `userId()`) est toujours présent dans l'interface
  pour permettre le routage dans le service et la corrélation côté client.
- Quand le destinataire varie selon le type de notification (ex: module social), exposer une méthode
  `userId()` dans l'interface pour que le service puisse router sans switch supplémentaire.

### 6.2 Mapper `XxxEventNotificationMapper` (`infrastructure/out/messaging/mapper/`)

- Classe `final` avec méthode `static` uniquement.
- Convertit un événement domaine (`XxxEvent`) en `Optional<XxxNotification>`.
- Utilise le **pattern matching** `switch` (`case XxxEvent.YyyEvent yyy -> ...`).
- Retourne `Optional.empty()` pour les événements sans notification (ex: événements internes).
- **Jamais** de logique métier — uniquement du mapping de champs.

```java
public final class GameEventNotificationMapper {
    private GameEventNotificationMapper() {
    }

    public static Optional<GameNotification> toNotification(GameEvent event) {
        if (isNull(event)) return Optional.empty();

        return switch (event) {
            case GameEvent.GameCreatedEvent e -> Optional.of(
                    new GameNotification.GameCreatedNotification(
                            e.gameId(), e.topicId(), e.player1Id(), e.player2Id()
                    )
            );
            case GameEvent.GameEndedEvent e -> Optional.of(
                    new GameNotification.GameEndedNotification(
                            e.gameId(), e.winnerId(), e.player1FinalScore(), e.player2FinalScore()
                    )
            );
            // ...
            default -> Optional.empty();
        };
    }
}
```

### 6.3 Service `XxxNotificationService` (`infrastructure/out/messaging/`)

- Annoté `@Service`.
- Écoute **tous** les événements du module via `@EventHandler` sur l'interface parente (`GameEvent`).
- Délègue immédiatement au mapper, puis envoie via `SimpMessagingTemplate`.
- Préfixe de destination : `/topic/{module}/{resourceId}` (ex: `/topic/games/{gameId}`, `/topic/social/{userId}`).
- Log les absences de mapping en `WARN`, pas en `ERROR` (certains événements intentionnellement
  ignorés).

```java

@Service
public class GameNotificationService {
    private static final String DESTINATION_PREFIX = "/topic/games/";
    private final SimpMessagingTemplate messagingTemplate;

    @EventHandler
    public void onGameEvent(GameEvent event) {
        GameEventNotificationMapper.toNotification(event)
                .ifPresentOrElse(
                        notification -> send(event.gameId(), notification),
                        () -> logger.warn("No notification mapping for: {}", event.getClass().getSimpleName())
                );
    }

    private void send(String gameId, GameNotification payload) {
        logger.debug("{} published: gameId={}", payload.type(), gameId);
        messagingTemplate.convertAndSend(DESTINATION_PREFIX + gameId, payload);
    }
}
```

### 6.4 Exposition HTTP des notifications (`GET /{id}/notifications`)

Le controller expose un endpoint qui rejoue les événements de l'event store et les convertit en
notifications, permettant aux clients de rejoindre une partie en cours et de récupérer l'historique :

```java

@GetMapping("/{gameId}/notifications")
public CompletableFuture<ResponseEntity<Collection<GameNotification>>> getGameNotificationsById(
        @PathVariable String gameId) {
    return getGameEventsUseCase.getEvents(gameId)
            .thenApply(events -> events.stream()
                    .map(GameEventNotificationMapper::toNotification)
                    .flatMap(Optional::stream)
                    .toList())
            .thenApply(ResponseEntity::ok);
}
```

---

## 7. Event Store Adapter (`infrastructure/out/messaging/adapter/`)

L'**Event Store Adapter** permet de lire les événements passés d'un aggregate depuis l'Axon Event Store,
sans passer par le bus de commandes.

### 7.1 Port sortant (`domain/port/out/`)

```java
public interface GameEventStorePort {
    List<GameEvent> findEventsByGameId(String gameId);
}
```

### 7.2 Adapter (`infrastructure/out/messaging/adapter/`)

- Implémente le port sortant.
- Injecte l'`EventStore` Axon (infrastructure) — **autorisé** uniquement dans cette couche.
- Lit le `DomainEventStream` par identifiant d'aggregate.
- Filtre uniquement les payloads correspondant à l'interface d'événement du module.

```java

@Component
public class GameEventStoreAdapter implements GameEventStorePort {

    private final EventStore eventStore;

    public GameEventStoreAdapter(EventStore eventStore) {
        this.eventStore = eventStore;
    }

    @Override
    public List<GameEvent> findEventsByGameId(String gameId) {
        List<GameEvent> events = new ArrayList<>();
        DomainEventStream stream = eventStore.readEvents(gameId);
        while (stream.hasNext()) {
            Object payload = stream.next().getPayload();
            if (payload instanceof GameEvent gameEvent) {
                events.add(gameEvent);
            }
        }
        return events;
    }
}
```

**Règles** :

- Cet adapter se place dans `infrastructure/out/messaging/adapter/`, pas dans `persistence/`.
- Le port sortant associé vit dans `domain/port/out/`.
- Le `QueryHandler` correspondant délègue à ce port, comme pour n'importe quel port sortant.
- **Jamais** d'accès à `EventStore` en dehors de cet adapter.

---

## 8. Infrastructure layer — Règles

### 8.1 Adapters sortants (`infrastructure/out/persistence/adapter/`)

- Implémentent les ports sortants du domaine.
- La seule couche autorisée à utiliser `JpaRepository`, `JpaSearchAdapter`, `XxxEntity`.
- Utilisent `XxxEntityMapper` pour la conversion.
- Instancient `AnnotationSearchableEntity` à partir de la classe JPA (voir §8.3).

```java

@Component
public class QuestionRepositoryAdapter implements QuestionRepositoryPort {
    private final QuestionJpaRepository questionJpaRepository;
    private final JpaSearchAdapter<QuestionEntity> questionJpaSearchAdapter;

    public QuestionRepositoryAdapter(QuestionJpaRepository questionJpaRepository) {
        this.questionJpaRepository = questionJpaRepository;
        this.questionJpaSearchAdapter = new JpaSearchAdapter<>(
                questionJpaRepository,
                new AnnotationSearchableEntity(QuestionEntity.class)
        );
    }

    @Override
    @Transactional
    public void save(Question question) {
        questionJpaRepository.save(QuestionEntityMapper.toEntity(question));
    }

    @Override
    @Transactional(readOnly = true)
    public PageResult<Question> findAll(SearchCriteria searchCriteria) {
        return questionJpaSearchAdapter.findAllByCriteria(searchCriteria, QuestionEntityMapper::toDomain);
    }
}
```

### 8.2 Entités JPA — Règles

- Annotées `@Entity`, `@Table`, avec index sur les colonnes filtrées/triées fréquemment.
- Utiliser `@Setter @Getter` (Lombok) — pas de constructeur lombokisé sur les entités JPA.
- **Pas de champ `@Version`** : l'architecture est event-sourcée avec Axon. Le versioning optimiste
  est géré par le framework Axon sur l'event store, pas sur les entités de projection JPA.
- Déclarer `@Searchable` sur chaque champ filtrable (voir §8.3).
- Les relations `@OneToMany` utilisent `cascade = CascadeType.ALL, orphanRemoval = true` et
  `fetch = FetchType.EAGER` pour les collections petites et toujours nécessaires.

```java
// ✅ Correct — pas de @Version, indexes déclarés
@Setter
@Getter
@Entity
@Table(name = "question_entry", indexes = {
        @Index(name = "idx_question_entry_topic", columnList = "topic_id"),
        @Index(name = "idx_question_entry_status", columnList = "status")
})
public class QuestionEntity {

    @Id
    @Searchable(type = FieldType.STRING)
    @Column(name = "question_id", length = 255, nullable = false)
    private String questionId;
}

// ❌ Interdit — @Version inutile dans une architecture event-sourcée Axon
@Version
private Long version;
```

### 8.3 Champs recherchables — annotation `@Searchable`

**Ne pas créer d'enum `XxxSearchableEntity`.** Les champs filtrables/triables sont déclarés
directement sur l'entité JPA via l'annotation `@Searchable`.

```java

@Entity
@Table(name = "topic_entry")
public class TopicEntity {

    @Id
    @Searchable(type = FieldType.STRING)
    private String topicId;

    @Searchable(type = FieldType.STRING)
    private String name;

    @Searchable(type = FieldType.STRING)
    @Enumerated(EnumType.STRING)
    private TopicCategory category;

    @Searchable(type = FieldType.NUMBER)
    private int questionCount;

    @Searchable(type = FieldType.DATE)
    private Instant createdAt;
}
```

**Règle `alias`** : si le nom du champ dans le DTO de réponse (`XxxResponse`) diffère du nom JPA :

```java
// UserResponse expose "id" mais le champ JPA s'appelle "userId"
@Searchable(type = FieldType.STRING, alias = "id")
private String userId;
```

### 8.4 Mappers (`infrastructure/out/persistence/mapper/`)

- Classes `final` avec méthodes `static` uniquement.
- **Seule** classe autorisée à importer simultanément un type domaine et une entité JPA.
- `toEntity` doit renseigner **tous les champs** — ne jamais retourner une entité partiellement remplie.

```java
public final class QuestionEntityMapper {
    private QuestionEntityMapper() {
    }

    public static Question toDomain(QuestionEntity entity) {
        return new Question(
                entity.getQuestionId(), entity.getTopicId(), entity.getText(),
                entity.getAnswers(), entity.getCorrectAnswer(), entity.getStatus(),
                entity.getCreatorId(), entity.getUpdatedBy(),
                entity.getCreatedAt(), entity.getUpdatedAt()
        );
    }

    public static QuestionEntity toEntity(Question question) {
        QuestionEntity entity = new QuestionEntity();
        entity.setQuestionId(question.questionId());
        entity.setTopicId(question.topicId());
        entity.setText(question.text());
        entity.setAnswers(question.answers());
        entity.setCorrectAnswer(question.correctAnswer());
        entity.setStatus(question.status());
        entity.setCreatorId(question.creatorId());
        entity.setUpdatedBy(question.updatedBy());
        entity.setCreatedAt(question.createdAt());
        entity.setUpdatedAt(question.updatedAt());
        return entity;
    }
}
```

### 8.5 Controllers (`infrastructure/in/api/`)

- Injectent **uniquement** des ports entrants (`domain/port/in/`).
- **Jamais** de `CommandGateway`, `QueryGateway`, ou repository directement.
- Retournent des DTOs (`XxxResponse`), jamais des types domaine.
- Pour les endpoints de création, retourner `201 Created` avec l'URI de la ressource.
- L'identifiant de la ressource est toujours généré dans le controller via `UUID.randomUUID()`.
- L'identifiant utilisateur connecté est récupéré via `SecurityHelper.getUserId()`.
- L'endpoint de recherche paginée est un `@PostMapping("/search")` acceptant un `SearchRequest`.

```java

@RestController
@RequestMapping("/api/questions")
public class QuestionController {


    public static final String QUESTIONS_ENDPOINT = "/api/questions";

    @PostMapping
    public CompletableFuture<ResponseEntity<IdResponse>> createQuestion(
            @RequestBody @Valid CreateQuestionRequest request) {
        String questionId = UUID.randomUUID().toString();
        String creatorId = SecurityHelper.getUserId();
        return createQuestionUseCase
                .create(questionId, request.topicId(), request.text(),
                        request.answers(), request.correctAnswer(), creatorId)
                .thenApply(_ -> ResponseEntityBuilder.creation(QUESTIONS_ENDPOINT, questionId));
    }

    @PostMapping("/search")
    public CompletableFuture<ResponseEntity<PageResponse<QuestionResponse>>> search(
            @RequestBody SearchRequest searchRequest) {
        SearchCriteria criteria = SearchRequestMapper.toSearchCriteria(searchRequest);
        return searchQuestionUseCase.search(criteria.filters(), criteria.sorts(), criteria.page())
                .thenApply(QuestionResponseMapper::toResponse)
                .thenApply(ResponseEntity::ok);
    }
}
```

### 8.6 Mappers de réponse (`infrastructure/in/api/mapper/`)

- Classes `final` avec méthodes `static` uniquement.
- Méthodes : `toResponse(DomainModel)`, `toResponse(PageResult<DomainModel>)`.
- `toResponse(PageResult<...>)` délègue à `SearchResponseMapper.toSearchResponse(...)`.

```java
public final class TopicResponseMapper {
    private TopicResponseMapper() {
    }

    public static TopicResponse toResponse(Topic topic) {
        return new TopicResponse(
                topic.topicId(), topic.name(), topic.description(),
                topic.category(), topic.status(), topic.creatorId(),
                topic.updatedBy(), topic.questionCount(),
                topic.createdAt(), topic.updatedAt()
        );
    }

    public static PageResponse<TopicResponse> toResponse(PageResult<Topic> pageResult) {
        return SearchResponseMapper.toSearchResponse(pageResult, TopicResponseMapper::toResponse);
    }
}
```

### 8.7 `DataSeeder` / composants de démarrage

- Injectent uniquement des ports entrants.
- Activés via `@Value("${app.seed-data.enabled:false}")` — toujours désactivés par défaut.
- Vérifient l'existence avant création (idempotence).
- **Jamais** de `CommandGateway`/`QueryGateway` directement.

```java
// ✅ Correct — via méthodes default bloquantes
createTopicUseCase.createAndWait(topicId, "Sciences","...",TopicCategory.SCIENCE, ADMIN_USER_ID);
approveQuestionUseCase.

approveAndWait(questionId, ADMIN_USER_ID);
```

---

## 9. Recherche paginée — Pattern complet

### Query object

```java
public interface TopicQuery {
    record TopicSearchQuery(
            List<FilterCriteria> filters,
            List<SortCriteria> sorts,
            PageCriteria page
    ) implements TopicQuery, SearchQuery {
    }
}
```

### Chaîne complète

```
SearchRequest (HTTP body)
  → SearchRequestMapper.toSearchCriteria()                   [infrastructure/mapper commun]
  → new XxxQuery.XxxSearchQuery(filters, sorts, page)        [controller]
  → SearchXxxUseCase.search(XxxSearchQuery)                  [port entrant]
  → QueryGateway → XxxSearchQuery                            [application/service]
  → XxxQueryHandler.handle(XxxSearchQuery)                   [application/handler]
  → XxxRepositoryPort.findAll(XxxSearchQuery)                [port sortant]
  → XxxRepositoryAdapter → JpaSearchAdapter                  [infrastructure/adapter]
     → AnnotationSearchableEntity(XxxEntity.class)
  → PageResult<XxxEntity> → PageResult<Xxx>                  [mapper]
  → XxxResponseMapper.toResponse(PageResult<Xxx>)            [infrastructure/in/api/mapper]
  → PageResponse<XxxResponse>                                [HTTP response]
```

### Alignement DTO ↔ entité JPA

| Situation                                            | Action                                                     |
|------------------------------------------------------|------------------------------------------------------------|
| Nom identique dans `XxxEntity` et `XxxResponse`      | `@Searchable(type = FieldType.XXX)` — pas d'alias          |
| Nom différent (ex: `userId` JPA, `id` dans Response) | `@Searchable(type = FieldType.XXX, alias = "id")`          |
| Renommage d'un champ dans `XxxResponse`              | Mettre à jour `alias` sur le champ JPA correspondant       |
| Nouveau champ filtrable                              | Ajouter `@Searchable` sur le champ JPA + test d'alignement |

---

## 10. Conventions de nommage

| Concept                   | Convention                                    | Exemple                                                |
|---------------------------|-----------------------------------------------|--------------------------------------------------------|
| Port entrant              | `XxxUseCase`                                  | `GetUserUseCase`                                       |
| Port sortant              | `XxxRepositoryPort` / `XxxPort`               | `UserRepositoryPort`, `PasswordEncoderPort`            |
| Port event store          | `XxxEventStorePort`                           | `GameEventStorePort`                                   |
| Adapter sortant JPA       | `XxxRepositoryAdapter`                        | `UserRepositoryAdapter`                                |
| Adapter event store       | `XxxEventStoreAdapter`                        | `GameEventStoreAdapter`                                |
| Service applicatif        | `XxxCommandService` / `XxxQueryService`       | `UserCommandService`                                   |
| Query handler             | `XxxQueryHandler`                             | `UserQueryHandler`                                     |
| Projection                | `XxxProjection`                               | `UserProjection`                                       |
| Saga                      | `XxxSaga` (préfixe décrivant le flux)         | `SyncBotGameSaga`                                      |
| Deadlines (constantes)    | `XxxDeadline` (interface dans `domain/model`) | `GameDeadline`                                         |
| Sous-agrégat              | `XxxAggregate` (dans `domain/aggregate/`)     | `GamePlayerAggregate`, `GameRoundAggregate`            |
| Mapper entité→domaine     | `XxxEntityMapper`                             | `UserEntityMapper`                                     |
| Mapper domaine→DTO        | `XxxResponseMapper`                           | `UserResponseMapper`                                   |
| Mapper event→notification | `XxxEventNotificationMapper`                  | `GameEventNotificationMapper`                          |
| Entité JPA                | `XxxEntity`                                   | `UserEntity`                                           |
| Repository JPA            | `XxxJpaRepository`                            | `UserJpaRepository`                                    |
| Notification WebSocket    | `XxxNotification` (interface + records)       | `GameNotification`, `SocialNotification`               |
| Service notification      | `XxxNotificationService`                      | `GameNotificationService`, `SocialNotificationService` |
| Champs recherchables      | `@Searchable` sur `XxxEntity`                 | ~~`UserSearchableEntity`~~ supprimé                    |
| Exception base            | `XxxProblem`                                  | `UserProblem`, `QuestionProblem`                       |
| Exceptions concrètes      | `XxxExceptions` / `XxxProblems`               | `GameExceptions`, `UserProblems`                       |
| Constantes métier         | `XxxRules` (interface ou final class)         | `TopicRules`, `GameRules`                              |
| Nommage des classes       | PascalCase strict                             | `UserRepositoryPort` (**pas** `userRepositoryPort`)    |

---

## 11. Checklist de validation

Après implémentation d'un module, exécuter ces vérifications :

```bash
# Bootstrap workspace (ordre défini dans workspace.yml)
make check
make boostrap

# Dans ce monorepo, adapter les chemins :
#   services/quizup-<service>/quizup-<service>-domain/src/main/java/...
#   services/quizup-<service>/quizup-<service>-infrastructure/src/main/java/...

# Aucun import infrastructure dans le domaine
grep -r "infrastructure" src/main/java/.../domain/
# → Doit retourner 0 résultats

# Aucun repository dans la couche application
grep -r "Repository" src/main/java/.../application/
# → Doit retourner 0 résultats

# Aucun CommandGateway/QueryGateway dans l'infrastructure
grep -r "CommandGateway\|QueryGateway" src/main/java/.../infrastructure/
# → Doit retourner 0 résultats

# Aucune entité JPA dans application ou domain
grep -r "Entity\|@Entity" src/main/java/.../domain/ src/main/java/.../application/
# → Doit retourner 0 résultats

# Aucun @Version sur les entités JPA (architecture event-sourcée)
grep -r "@Version" src/main/java/.../infrastructure/out/persistence/entity/
# → Doit retourner 0 résultats

# Aucun enum XxxSearchableEntity
grep -r "SearchableEntity" src/main/java/.../infrastructure/out/persistence/entity/
# → Doit retourner 0 résultats

# Vérifier que toEntity() remplit tous les champs
grep -A 20 "toEntity" src/main/java/.../infrastructure/out/persistence/mapper/
# → Vérifier manuellement que chaque setter est appelé

# Aucun accès direct à EventStore hors des adapters event store
grep -r "EventStore" src/main/java/.../domain/ src/main/java/.../application/
# → Doit retourner 0 résultats

# Aucun accès direct à SimpMessagingTemplate hors de XxxNotificationService
grep -r "SimpMessagingTemplate" src/main/java/.../domain/ src/main/java/.../application/
# → Doit retourner 0 résultats

# Beans saga déclarés transient
grep -B2 "@Autowired" src/main/java/.../application/saga/
# → Tous les @Autowired doivent être précédés de "transient"

# Toutes les deadlines annulées dans les @EndSaga
grep -n "EndSaga\|cancelSchedule\|cancelAll" src/main/java/.../application/saga/
# → Vérifier manuellement que chaque @EndSaga appelle cancelAll() ou l'équivalent

# Vérifier les ports entrants : méthodes non-default prennent un Command/Query
grep -rn "CompletableFuture" src/main/java/.../domain/port/in/
# → Vérifier manuellement

# Aucune logique dans les méthodes default des ports entrants
# → Les default se limitent à : return methode(new XxxCommand(...)) ou methode(...).join()
```

---

## 12. `quizup-starter` — Spring Boot Starter transverse

Le module `quizup-starter` est un **Spring Boot Auto-Configuration** inclus dans tous les
microservices. Il configure automatiquement les composants transverses via `MicroserviceProperties`
(préfixe `microservice:`).

### 12.1 Fonctionnalités auto-configurées

| Auto-configuration                 | Propriété de contrôle                    | Rôle                                |
|------------------------------------|------------------------------------------|-------------------------------------|
| `CorsAutoConfiguration`            | `microservice.cors.enabled`              | CORS configurable                   |
| `SwaggerAutoConfiguration`         | `microservice.swagger.enabled`           | OpenAPI / Swagger UI                |
| `ExceptionAutoConfiguration`       | `microservice.exception-handler.enabled` | Handler global + intercepteurs Axon |
| `ResourceServerAutoConfiguration`  | `microservice.resource-server.enabled`   | OAuth2 JWT (issuer + JWK)           |
| `WebSocketAutoConfiguration`       | `microservice.websocket.enabled`         | STOMP / SockJS                      |
| `ActuatorAutoConfiguration`        | `microservice.actuator.enabled`          | Spring Boot Actuator                |
| `PasswordEncoderAutoConfiguration` | —                                        | Bean `BCryptPasswordEncoder`        |

### 12.2 `SecurityHelper` — extraction du contexte JWT

`SecurityHelper` (`quizup-starter`) est la seule source pour extraire l'identité de l'appelant
dans les controllers :

```java
// Dans les controllers uniquement
String userId = SecurityHelper.getUserId();          // lève MissingUserIdException si absent
String email = SecurityHelper.getUserEmail();
Optional<String> maybeId = SecurityHelper.findUserId(); // version nullable

QuizUpPrincipal principal = SecurityHelper.getPrincipal();
boolean authenticated = SecurityHelper.isAuthenticated();
```

**Ne jamais** accéder à `SecurityContextHolder` directement depuis les controllers — utiliser
exclusivement `SecurityHelper`.

### 12.3 `QuizUpConstants` — identifiants système

Les IDs système immuables sont centralisés dans `common/domain/constant/QuizUpConstants` :

```java
QuizUpConstants.ADMIN_USER_ID  // "0ada9a20-2198-4014-9ed0-57d0cc82fb42"
QuizUpConstants.BOT_USER_ID    // "bccadaad-488e-40db-89cf-8b20f9c29a79"
QuizUpConstants.TEST_USER_ID   // "3a568de1-94a7-4523-bb2a-20e111ccf9bf"
```

Utiliser ces constantes dans les `DataSeeder` et les Sagas (ex: `BotGameSaga`, `LobbySaga`).

### 12.4 Gestion des erreurs Axon

`ProblemCommandHandlerInterceptor` et `ProblemQueryHandlerInterceptor` (dans le starter)
interceptent les `BaseProblem` lancées dans les handlers Axon et les propagent au `GlobalExceptionHandler`.
Il n'est **pas** nécessaire d'ajouter de logique de catch dans les handlers — lancer directement :

```java
// ✅ Correct — dans un QueryHandler ou CommandHandler
throw new UserProblems.UserNotFoundProblem(userId);
```

---

| Couche            | Peut importer                                                                 | Ne peut PAS importer                             |
|-------------------|-------------------------------------------------------------------------------|--------------------------------------------------|
| `domain/`         | types domaine, `common.domain.*`, Axon (`@Aggregate`, `AggregateLifecycle`)   | Spring, JPA, `infrastructure.*`, `application.*` |
| `application/`    | `domain.*`, `common.*`, Axon (gateways, handlers, `@Saga`, `DeadlineManager`) | `infrastructure.*`, JPA, Spring Web              |
| `infrastructure/` | tout                                                                          | — (couche la plus externe)                       |

---

## 13. Pourquoi pas de `@Version` sur les entités JPA ?

Dans QuizUp, la cohérence des données d'écriture est assurée par **Axon Event Sourcing** :

- Les **aggregates** Axon maintiennent leur propre version interne via l'event store.
- Le verrouillage optimiste est géré nativement par Axon (rejet des commandes concurrentes sur le
  même aggregate via la séquence d'événements).
- Les **entités JPA** (`*Entity`) ne sont que des **projections read-only** mises à jour par les
  `@EventHandler`. Elles ne sont jamais modifiées directement par des commandes métier.
- Ajouter `@Version` sur une entité de projection serait redondant et pourrait provoquer des
  `OptimisticLockException` injustifiées lors de replays d'événements.

