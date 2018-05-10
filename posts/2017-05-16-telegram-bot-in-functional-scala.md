---
title: "Developing a Telegram bot by applying Functional Scala"
intro: " In this article I'll explain how I build a Telegram bot by applying Functional Scala. Libraries used are: FS2, Circe, Doobie and Atto"
author: "mark"
---

In The Netherlands we have a good train network. However from time to time the Nederlandse Spoorwegen (NS - the guys who run the trains) have disruptions. I want to have notifications, so I can just check my phone when waking up and see if there is any trouble.

To check out the source, please check ns-tracker

## Knowledge prerequisites

Before continue reading this article you should have a understanding of:

- API’s and formats like XML & JSON
- Advanced Scala (implicits, type classes, generics, etc)
- Functional concepts like: Monads & Monad Transformers

## The stack

I’ve used the following libraries:

- Cats - Functional Programming constructs (like Monad, Monad Transformers, etc)
- Postgres - For storing state in database
- Doobie - For JDBC database
- Circe - JSON encoding and decoding
- fs2 - Pull based stream processing. Offers also Task, a alternative to Future
- Atto - For parsing Telegram commands

## Telegram

With Telegram you will be able to create so called bots. This is something which WhatsApp doesn’t offer. What does it mean to develop a Telegram bot?

- You can start talking to a bot and Telegram will buffer the messages
- Telegram will act a mediator. Any messages posted to a bot go through Telegram. You as bot developer have to either long poll for updates or set up a web hook
- Each command is processed by your logic. That means you are responsible for persisting state and handling the commands
- For creating a basic bot you need to retrieve the messages which are posted in the bot and respond
- You can send a user a message any time

### Creating a bot and get your botId

You can create a bot by talking to the BotFather. By entering /newbot you’ll get a botId which is needed in the API calls

### Register your server

You can either use long polling or web hooks to retrieve messages posted to a Telegram bot. I’ll explain how I did setup web hooks.

You have to POST https://api.telegram.org/bot{botId}/setWebhook with a form-urlencoded body which contains url={url_to_your_message_handler_endpoint}.

Whenever a user posts a message to your Telegram bot now, Telegram will post it to url_to_your_message_handler_endpoint.

A message may look like this:

```json
{
    "update_id": 169800632,
    "message": {
        "message_id": 646,
        "from": {
            "id": 348940006,
            "first_name": "Mark",
            "last_name": "de Jong"
        },
        "chat": {
            "id": 348940006,
            "first_name": "Mark",
            "last_name": "de Jong",
            "type": "private"
        },
        "date": 1494929704,
        "text": "test"
    }
}
```

### Send a message back

Now you want to send back a message. You can use this endpoint to send a message back:

`POST https://api.telegram.org/bot{botId}/sendMessage` with also a `form-urlencoded` body contains these variables:

- chat_id - The id of the chat
- text - The actual message

It will return you a JSON with the message you posted
Nederlandse Spoorwegen data

To retrieve data from the Nederlandse Spoorwegen (NS), we can talk to their API. To be specific we can use the endpoint `GET https://webservices.ns.nl/ns-api-avt?station=Zwolle` to retrieve all voyages which depart from that station. You’ll need to use basic http authentication to actually retrieve data from this endpoint.

The data is formatted in XML and looks like this:

```xml
<ActueleVertrekTijden>
  <VertrekkendeTrein>
    <RitNummer>535</RitNummer>
    <VertrekTijd>2017-05-16T11:45:00+0200</VertrekTijd>
    <VertrekVertraging>PT2M</VertrekVertraging>
    <VertrekVertragingTekst>+2 min</VertrekVertragingTekst>
    <EindBestemming>Groningen</EindBestemming>
    <TreinSoort>Intercity</TreinSoort>
    <RouteTekst>Assen</RouteTekst>
    <Vervoerder>NS</Vervoerder>
    <VertrekSpoor wijziging="true">6</VertrekSpoor>
  </VertrekkendeTrein>
</ActueleVertrekTijden>
```

There is information like at which time the train departs, at which stations it will stop at, if there is any delay, etc.

## High level architecture

The program contains basically two processes

- A interval based loop which retrieves a set of unique stations which have a watch. For each station it will contact the NS API. Whenever there is a disruption it will use the Telegram sendMessage API to notify the user. When this succeeds it will store that the user is notified in the database. This process will recur over time by a interval
- A HTTP server which is used to listen webhooks (called by Telegram)

In functional programming we tend to keep our logic centered and push all the side-effects to the boundary of our application. There are numerous examples in functional programming for that: free monads, fs2, etc.

One of the components of our program is the Telegram command to reply pipeline. From a webhook we extract the message (command) and pass it into a pipeline which translate the command to actual reply (with side effects). Let’s dive into how create such a pipeline.

It would be a bad design to couple in the HttpRequest (from webhooks) or HttpResponse (from long polling) into the pipeline. The message is just a String and we need to act accordingly. By decoupling this, we could plug this pipeline either with long polling or webhooks.

## Telegram command to reply pipeline

So for each command we need to:

- Parse the actual command in to a case class
- Use the case class to do stuff with the database (query, insert or remove a watch)
- Respond back to the user

It’s a good practice to define the small steps required to achieve your end goal. Now let’s solve all the requirements step by step.


### Parsing

How do we parse the Telegram messages? We could use a regular expression, but it would be better to use actual parsers. Rob Norris wrote a little and comprehensive parsing library called Atto.

For this bot I made it possible to track, remove and list your watches by these commands:

- track “from-station” “to-station” from-time till-time - Add a watch for voyage track for any disruptions. Note that and should surrounded by double-quotes. With time, note that and should be in a 24h format (00:00)
- remove id - Remove a watch by id
- list - List all watches and their id (to remove it)

Let’s first define our commands:

```scala
sealed trait BotCommand
object BotCommand {
  case class TrackVoyage(fromStation: String, toStation: String, fromHour: Time, toHour: Time) extends BotCommand
  case class RemoveVoyage(id: Int) extends BotCommand
  case object ListVoyages extends BotCommand
}
```

Parsing this with Atto is quite simple:

```scala
object Parsing {
  private def fixed(n: Int): Parser[Int] =
    count(n, digit).map(_.mkString).flatMap { s =>
      try ok(s.toInt) catch {
        case e: NumberFormatException => err(e.toString)
      }
    }

  private val time = (fixed(2) <~ char(':') |@| fixed(2)) map Time.apply
  private val station = stringLiteral

  val trackVoyage: Parser[BotCommand.TrackVoyage] =
    (string("track") ~> (spaceChar ~> station) |@| (spaceChar ~> station) |@| (spaceChar ~> time) |@| (spaceChar ~> time)) map BotCommand.TrackVoyage.apply

  val removeVoyage: Parser[BotCommand.RemoveVoyage] =
    (string("remove") ~> (spaceChar ~> int)) map BotCommand.RemoveVoyage.apply

  val listVoyages: Parser[BotCommand.ListVoyages.type] =
    string("list") >| BotCommand.ListVoyages
}
```

### Creating handlers

Now we got the parsers we need to create handlers for each command. So what is needed for a command handler?

- We need a parser which extracts the actual command as a case class (we’ve used coded that as a Parser[A])
- There is a choice between multiple handlers. Whenever the parsing succeeds it should continue with the supplied function (which has the extracted command and performs database queries) and when it fails to parse, it should try the next handler
- We have branching in our command handling. The entered command might a good one, or one which will fail. We need to verify that by using assertions or database queries. In the end the format of result will be the same (A user expects a message what his command did)

#### Partial functions

So let’s start with the choice between multiple handlers. We can model that with a PartialFunction. The nice thing about PartialFunction is that they are composable. You can combine multiple PartialFunction’s by using `orElse` You can create a partial function by using Function.unlift. The signature looks like: `def unlift[T, R](f: T => Option[R]): PartialFunction[T, R]` which is in the standard Scala library.

So a quick a example:

```scala
val a = Function.unlift[String, Int](str => if(str == "1") Some(1) else None)
val b = Function.unlift[String, Int](str => if(str == "2") Some(2) else None)
val c = a orElse b

def process(i: String) = c.applyOrElse(i, (_: String) => 0)

process("1") // will return 1
process("3") // will return 0
```

This is of course a simple example, but it will work with our little `Parser[A]`. We can feed that a String using parseOnly which will return a `ParseResult[A]` which is convertible to a `Option[A]`. That’s exactly what we need for PartialFunction!
Branching and running database effects

So now we get to the part where we need branch our computations and run database effects. Like stated before we are using Doobie for the database. Running a query will return us a `Task[A]` and requires us to have a `transactor.Transactor[Task]` to turn `Query[A]` into `Task[Vector[A]]` for example.

To have `transactor.Transactor[Task]` available, we can use a type `Prg[A] = ReaderT[F, transactor.Transactor[Task], A]]` for this matter. Where `F[_]` is a `Monad`. You don’t need to pass this `transactor.Transactor[Task]` around when writing a handler, we push this concern to the boundary of our app.

Whenever a query returns not enough results or the entered information is incorrect we need to return a error or continue whenever everything is alright. In other words branching. We can use `Either[L, R]` to do branching (which is right biased in Scala 2.12 and forms a Monad). However we need to evaluate effects of `Task[_]` (`Task[_]` is also a Monad). So we’ll need a `type Prg[A] = EitherT[Task, String, A]` (monad transformer). This also forms a `Monad`, so we can put this into the `F[_]` of `type Prg[A] = ReaderT[F, transactor.Transactor[Task], A]`.

This will give us a `type Prg[A] => ReaderT[EitherT[Task, String, ?], transactor.Transactor[Task], A]]`. What is this `?` synax. Basically it is syntax sugar for type lambda’s. You can find more info on that on the kind-projector project.

To actual lift expressions `Option[A]`, `Query[A]` or `Task[A]` to this monad transformer stack I create several combinators which ease the process. I’ve left those out in this article, but you may see them in the final example. In case you are curious, you could check the source code to see their implementation.

## Putting it together

So how do we put this together? The handle combinator would look something like this:

```scala
def handle[A](p: Parser[A])(f: A => ReaderT[EitherT[Task, String, ?], transactor.Transactor[Task], String]]) =
    Function.unlift[String, ReaderT[Task, transactor.Transactor[Task], String]](x =>
      p.parseOnly(x).map(y => f(x).mapF(_.fold(identity, identity))).option
    )
```

So let’s break this down. The arguments are

- `p: Parser[A]` is required to extract `A` from a `String`
- `f: A => ReaderT[EitherT[Task, String, ?], transactor.Transactor[Task], String]]` is the actual handler function. It returns the monad stack as composed before and it consumes the parsed `A`

In the implementation of the handler combinator, `Function.unlift` will consume String and return a `ReaderT[Task, transactor.Transactor[Task], String]`. First we use the parse the string using `p.parseOnly(x)`. This will return a `ParseResult[A]` which has a map combinator. After that we apply our f function to get a `ReaderT[EitherT[Task, String, ?], transactor.Transactor[Task], String]]`. After that we use `mapF` to remove the disjunction part (`EitherT`) by `_.fold(identity, identity)`. After that we use the `.option` combinator to turn `ParseResult[ReaderT[Task, transactor.Transactor[Task], String]]` into a `Option[ReaderT[Task, transactor.Transactor[Task], String]]`. Remember that we need to return a `Option` for `Function.unlift`. So that concludes the implementation of the handle combinator. Below a example of the usage of handle:

```scala
val add = handle(Parsing.trackVoyage) { req =>
  for {
    _ <- guard(Stations.names.contains(req.fromStation), s"Station '${req.fromStation}' not found")
    _ <- guard(Stations.names.contains(req.toStation), s"Station '${req.toStation}' not found")
    _ <- update(VoyageSubscription(req.fromStation, req.toStation, req.fromHour, req.toHour))(Queries.insertSubscription)
  } yield "Added"
}

val remove = handle(Parsing.removeVoyage) { req =>
  for {
    count <- update0(Queries.removeSubscription(req.id, req.chatId))
    _ <- guard(count > 0, s"Failed to removed voyage with id ${req.id}")
  } yield "Removed"
}

val list = handle(Parsing.listVoyages) { req =>
  for {
    voyages <- listQuery(Queries.listSubscriptions(req.chatId))
  } yield
    if (voyages.nonEmpty) BotReply(voyages.map(v => s"${v.id} | ${v.value.fromStation} ->> ${v.value.toStation}").mkString("\n"))
    else "You don't have any voyages yet!"
}

val handlers = add orElse remove orElse list

def handleRequest(xa: transactor.Transactor[Task])
                 (r: String): Task[String] = {
  val fail = (_: String) => ReaderT[Task, transactor.Transactor[Task], String](_ => Task.now("Invalid command"))

  handlers.applyOrElse(r, fail).run(xa)
}
```

As you can see, it’s very concise to define handlers. Like I said before I’ve defined monad transformer combinators like `guard`, `update`, `update0`, `listQuery`, etc for validating, retrieving and update/inserting data (you can see their implementation at the repository).

So to recap, how did we design this pipeline?

- We split up our problems in small steps
- For each step we evaluate which solutions we could apply (by experimenting or consulting our functional programming tools)
- We model our side-effects and branching explicitly
- We push side-effects to the boundary of the program

# Stream processing with fs2

Like stated before we have two processes in our program. One for handling HTTP requests and one for pulling the database from time to time and check if there any disruptions for the interested watchers. I’ll show and explain the latter.

This is the code for pulling the database and notify the watcher in case of a disruption:

```scala
//a `Task[_]` which sends a telegram message and stores that we've notified the user in the database
def notify(sub: Entity[VoyageSubscription], delayedVoyage: Voyage): Task[Int] = ???

val notifier: Stream[Task, Unit] = for {
  _ <- fs2.time.awakeEvery(60.seconds)
  voyageSubscription <- Queries.uniqueSubscribedStations.process.transact(xa)
  voyages <- Stream.eval(NsApi.voyages(voyageSubscription.fromStation).run(cfg.ns))
  delayedVoyage <- Stream.emits(voyages.filter(x => x.delay.nonEmpty || x.comments.exists(_.contains("Rijdt niet"))))
  sub <- Queries.subscriptions(voyageSubscription.subscriptionIds, delayedVoyage.ritNr).process.transact(xa)
  _ <- if(delayedVoyage.destinations.contains(sub.value.toStation)) Stream.eval(notify(sub, delayedVoyage)) else Stream.emit(())
} yield ()
```

We can build up a Stream[F, A] by using a for-comprehension. This is because Stream is also a Monad.

- `_ <- fs2.time.awakeEvery(60.seconds)` - will sleep the stream for 60 seconds
- `voyageSubscription <- Queries.uniqueSubscribedStations.process.transact(xa)` - Will retrieve all stations which are been watched by the users. `.process` will turn this `Query[VoyageSubscriptions]` into `Stream[Task, VoyageSubscriptions]`
- `voyages <- Stream.eval(NsApi.voyages(voyageSubscription.fromStation).run(cfg.ns))` - Will call the NS API and retrieve a `List[Voyage]`. The combinator `Stream.eval` will evaluate a `Task[A]` and put it into the `Stream[Task, A]`
- `delayedVoyage <- Stream.emits(voyages.filter(x => x.delay.nonEmpty || x.comments.exists(_.contains("Rijdt niet"))))` - Will only filter delayed voyages. After that we use Stream.emits to emit a `Seq[A]` to a `Stream[Task, A]`
- `sub <- Queries.subscriptions(voyageSubscription.subscriptionIds, delayedVoyage.ritNr).process.transact(xa)` - Will retrieve a list of watches which are not notified yet. Note that we use `.process` again to retrieve a query as a `Stream[Task, A]`.
- `_ <- if(delayedVoyage.destinations.contains(sub.value.toStation)) Stream.eval(notify(sub, delayedVoyage)) else Stream.emit(())` - Will check if `delayedVoyage.destinations` contains the target station of the watcher. If so, we’ll notify otherwise we just continue.

As you can see it’s very easy build a pull based stream processor by using fs2 and doobie.

# Conclusion and future work

I liked writing code in the functional style in Scala. We explicitly capture side effects, push the effects to the outside of the program, pull based stream processing, easy configuration and excellent JSON encoding/decoding. The quality of these functional libraries are excellent.

The work on this bot is not complete. It needs circuit breakers, setting up a watch can be conversational, etc.
