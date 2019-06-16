---
title: "A functional ecosystem"
intro: "At DHL I built a microservice using cats, cats-effect, cats-tagless, refined, doobie, http4s and ZIO"
author: "mark"
---

In this post I would like to go over some of the tech I used to build a new micro-service at DHL and why these technologies and methodologies could be interesting as well for you. I had the freedom to pick new technologies. I would like to thank DHL Netherlands to give me this opportunity.

Back to the project! I'm quite fond of functional programming and I decided to roll with a functional stack. The stack includes http4s, circe, refined, doobie, cats, cats-tagless, cats-effect and on top of that ZIO.

I think there is some great material already out there about cats, http4s, circe, discipline, scalacheck and ZIO.

- [Introduction to Cats - Scala with Cats](https://underscore.io/books/scala-with-cats/)
- [Quick ZIO intro/motivation and John talks about Queue's - John de Goes](https://www.youtube.com/watch?v=8JLprl34xEw)
- [http4s - pure, typeful, functional HTTP in Scala](https://www.youtube.com/watch?v=urdtmx4h5LE)
- [STM - John de Goes & Wiem Zine Elabadine](https://www.youtube.com/watch?v=d6WWmia0BPM)
- [On testing tagless final algebras with discipline](https://www.iteratorshq.com/blog/tagless-with-discipline-testing-scala-code-the-right-way/)
- [Decorate your types with refined](https://www.youtube.com/watch?v=zExb9x3fzKs)

## Preciser types with refinement types

In a typical Scala application, you model data structures with primitive types such as `String`, `Int` and so forth. In a lot of cases, these primitive types are too wide, in other words, they accept too many values. This makes it harder to test your function because your function and data structures will accept a lot of values and can, therefore, be in a lot of states. To constrain these primitive types we can use _refinement types_.

A basic example of this. In my backend we referrer to a depot by a depot code. This is 3 characters long code. In a refinement type I would describe it like this:

### Basic example

```scala
type DepotCode = Size[Equal[W.`3`.T]]

def getUsers(depotCode: String Refined DepotCode): Task[List[User]] = ???
```

In this example, I have a method `getUsers` which has a refined `String` type which only allows a `String` of 3 characters. This is incredibly useful because the method is easier to test and you don't need to check if the `depotCode` is a `String` of 3 characters long.

### What else?

This is a basic example of refinement types. You can also use variable sized strings (3 to 200 chars), regular expressions, etcetera. The variable sized strings could be useful to not lose data when you store it in a database like Postgres or MySQL.

There are modules for cats, circe, doobie and other libraries that deal with data to constrain your primitives. In my backend, I use circe to encode and decode JSON. With refinement types module for circe, I can be sure that an incoming payload from an HTTP endpoint is in the right shape for me to process further. This eliminates a lot of bugs and tests.

You can also do this by using lists and sets which are not empty like `NonEmptyList` and `NonEmptySet`. You can even go further and include the dimensions of a collection in a type by using dependent types. This could be useful for matrix operations which is relevant in machine learning.

## SQL is expressive, do not lose its power

In the past, I've been using Slick and Hibernate which make mappings to types (ORM's). While this adds type-safety I think there are some downsides to these approaches:

- Slick or Hibernate outputs SQL which you need to see for yourself if it's any good
- Slick or Hibernate is not an expressive as SQL (for example generate a time series and over each day do a sub-query)

Therefore I prefer Doobie over these solutions. Doobie has a specialized string interpolator for SQL queries. So you can write SQL queries as you are used to, but use string interpolation to safely insert values into your queries like this:

```scala
def list(userId: UserId): Query0[ExamResult] =
    sql"select exam_id, correct, total from exams where user_id = $userId".query[ExamResult]
```

This is a `Query0` statement which means it's not a `ConnectionIO` yet, to do that you can use combinators like `run`, `to[List]`,  `stream`, `unique` or `option` to get the right shape out of your database. `ConnectionIO` is similar to `DBIO` (as seen from Slick). It allows you to compose `ConnectionIO` statements through a for comprehension. Executing these statements as a whole makes it a transaction.

Another nice feature of Doobie is that you can check if the query type checks with your case class. In this example, it's `ExamResult`.

So `ExamResult` is defined as `case class ExamResult(id: String Refined ExamId, correct: Int, total: Int)`.

With the `check` method which is included in the test harness of doobie you can verify the query is correct:

```
  + Query0[ExamResult] defined at ExamRepository.scala:20

      select exam_id, correct, total from exams where user_id = ?

    + SQL Compiles and TypeChecks
    + P01 UUID  →  OTHER (uuid)
    + C01 exam_id VARCHAR (varchar) NOT NULL  →  String
    + C02 correct INTEGER (int4)    NOT NULL  →  Int
    + C03 total   INTEGER (int4)    NOT NULL  →  Int
```

Doobie is simple and works with any JDBC driver. This means you can start with an ordinary Postgres database and switch later to a CockroachDB, Citus, TimescaleDB or even Clickhouse database.

## Composability of transactional statements

In a backend, you either work with in-memory data structures that need to be modified or data-structures inside a database. If you use a database like Postgres or MySQL multiple statements can be composed together to run in a transaction. A transaction is atomic, which means all the changes happen at once or not.

### Doobie and tagless final

It's a common practice to group methods that query the database in a `Repository`. A repository is an interface to query a certain group of coherent entities. A little example:

```scala
trait EventRepository[F[_]] {
  def allEvents(offset: Long): Stream[F, AggregateEvent[Json]]
  def deleteStream(aggregateId: UUID): F[Int]
  def getEventsByAggregateId(aggregateId: UUID, fromSeqNumber: Option[Long] = None): Stream[F, Event[Json]]
  def insert(aggregateId: UUID, lastSeqNumber: Long, events: NonEmptyList[Event[Json]]): F[Int]
}
```

As you can see we have a tagless final interface for a repository. Why? Well, we want to implement _all_ of our repositories in terms of `ConnectionIO` (same thing as `DBIO` in Slick) to either choose compose multiple statements into a transaction or run one single method. To do the latter we need to transform the complete interface. Luckily cats-tagless has some utilities for that:

```scala
trait FunctorK[A[_[_]]] {
  def mapK[F[_], G[_]](af: A[F])(fk: F ~> G): A[G]
}
```

This may be daunting, but it's not that hard. If you look at type `A[_[_]]` we can fit in `EventRepository[F[_]]`. So for parameter `af` we could use `EventRepository[ConnectionIO]`. This implies that `F` is `ConnectionIO`. To get values out of a `ConnectionIO` doobie has a method `trans` on `Transactor` (which is a natural transformation). This method looks like this:


```scala
def trans(implicit ev: Monad[M]): ConnectionIO ~> M
```

If we want `M` to be a ZIO `Task` we are game! The library `cats-tagless` offers a nifty macro which makes it easy to derive a `FunctorK` from a tagless final interface:

```scala
implicit val functorK: FunctorK[EventRepository] = Derive.functorK[EventRepository]
```

I have a utility method which allows you to select a `ConnectionIO `repository and get back `Task` based version:

```scala
def pgRepo[K[_[_]]](f: PostgresRepos[ConnIO] => K[ConnIO])(implicit F: FunctorK[K]): K[Task] =
    F.mapK(f(postgresRepos))(trans)
```

Which let you write something like this `env.pgRepo(_.users).findById(userId)`. The `PostgresRepos` is a case class that contains all the repositories based on `ConnectionIO`. Thanks to the `FunctorK` instance we can transform the _complete_ algebra/interface to a `Task` based on.

But what if you want to compose multiple transaction statements? I use this method:

```scala
def pgTransact[A](tx: Monad[ConnIO] => PostgresRepos[ConnIO] => ConnIO[A]): Task[A] =
    trans(tx(monadConnIO)(postgresRepos))
```

And a little example here:

```scala
def deleteRows: Task[Unit] = env.pgTransact { implicit connIO => repos =>
    for {
        _ <- repos.courierEvents.deleteStream(userId.repr)
        _ <- repos.courierTokens.delete(userId)
        _ <- repos.exams.delete(userId)
    } yield ()
}

```

Et voila!

### A great tool

Tagless final works well with repositories, but can also work pretty well with other subsystems that work with data. This could be a REST or gRPC client interacting with a sub-system like Keycloak, Kubernetes, etc. You could also decorate your algebra with logging, caching, tracing or metrics. Or add timeouts and circuit breakers to all methods using a natural transformation.

Using discipline to test your tagless final algebras is a great tool to write tests that are not bound to a specific database or API. It lets you write down the semantics/laws of your algebras and you plug it to test for example a `ConnectionIO` based implementation or your test implementation which uses ZIO `Task`. If you decide to move a repository over to Cassandra, it's a matter of setting up your test harness to cope with Cassandra specific IO operations.

## What's next?

I think functional programming can add a lot more stuff to Scala. Scala offers the power to write (Embedded Domain Specific Languages) EDSL's like in Haskell. This means you embedded a micro-language in the host language itself. Such a language can describe data structures, but also HTTP/gRPC endpoints.

There are projects like `formulation`, `skeuomorph` and `scalaz-schema` which describe data structures to derive Encoders and Decoders, but also Schema's from data types. I think it's good to have explicit mappings of your data-structures in your code as you will eventually have to think about migrating and back/forward compatibility.

Projects like `endpoints`, `itinere` and `tapir` are there to describe HTTP endpoints. If you combine that with the projects from above you can remove the boilerplate of writing HTTP endpoints by hand as your business logic is mapped to these endpoints! You could see HTTP endpoints as encoders and decoders as well. With these endpoint libraries, you can derive a server, a client but also a Swagger/OpenAPI specification which can be offered to external consumers.

I think having these tools is crucial to prevent problems with the compatibility of your data inside event logs or external consumers of your API.
