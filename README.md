![amber](https://github.com/amberframework/site-assets/raw/master/images/amber-horizontal.png)

**Productivity. Performance. Happiness.**

_Amber makes building web applications fast, simple, and enjoyable - with fewer bugs and blazing fast performance._

[![Version](https://img.shields.io/github/tag/amberframework/amber.svg?maxAge=360&label=version)](https://github.com/amberframework/amber/releases/latest)
[![License](https://img.shields.io/github/license/amberframework/amber.svg)](https://github.com/amberframework/amber/blob/master/LICENSE)

# Welcome! Introducing Amber

<img src="./hi_amber.png" alt="Amber Framework Demo" width="275" height="auto">


_This is the current work in progress branch for the future of Amber v2._

**Amber** is a web application framework written in [Crystal](https://crystal-lang.org/) inspired by Kemal, Rails, Phoenix, Flutter and other popular application frameworks.

The original purpose of Amber was not to create yet another framework, but to take advantage of the beautiful Crystal language capabilities and provide engineers and the Crystal community with an efficient, cohesive, well maintained web framework that embraces the language philosophies, conventions, and guidelines.

This is still mostly true, however, in the era of AI things are changing. Amber is embracing the use of AI for coding help and has begun making significant changes to support enabling automous AI assistants (aka coding agents) for writing projects.

Amber borrows concepts that have already been battle tested and successful, and embraces new concepts through team and community collaboration and analysis, which also aligns with Crystal's philosophy.

## How Complete Is Amber?

An Amber application represents all aspects of a modern (2025 and beyond) web application.

1. MVC - proven pattern for managing requests and responses
2. ActiveRecord ORM - proven pattern for managing database records
3. Background jobs - 2 systems are present to get you started and then grow into as your app is successful
4. Cloud file storage - upload and store files for users, jobs, etc.
5. Users & authentication - every app has users and needs authentication
6. Transactional emails - send emails for important events
7. Audit logging - because SOC2 demands accountability for our actions
8. API Documentation Generator - because security demands we maintain knowledge of our code base to test it reguarly
9. Reactive views - because it's 2025 (or beyond) and we deserve a modern front-end system.
10. MCP - everyone is going to build AI native apps, welcome to the new future
11. SBOM - A _S_oftware _B_ill _O_f _M_aterials is necessary for mature certifications, so build with _success_ in mind


## How Amber Is Embracing AI

On our blog in April of 2023, it was declared that AI would be treated as a first-class citizen. But, what does that really mean? At the time, I had 3 points:

1. Enabling AI for the development process.
2. Helping generate and maintain documentation.
3. Creating training material for public documentation that can be published and eventually picked up for use in training SOTA models.

Well, a lot has changed since then. The good news is that those objectives are just as relavent now as they were when I put them forward.

### 1. Enabling AI For The Development Process

Over the last year and a half, code editors that empower AI models that aren't specifically trained on a framework or technology have made significant progress. Cursor is the primary code editor that I've been using since the very beginning. Copilot was a fun introduction, however the real power of developing with an AI model is when you are using a tool like Cursor, Windsurf and other AI-native development environments.

This has lead to the development of documentation as "rules" in the code base itself. Some documentation is explicitly written as rules for Cursor that will automatically be attached to the agents context window when it's doing work. Other documentation will just be markdown files in a `/help` directory. There's a combination of these two approaches that has been converging over the first half of 2025 that I think will become the prominent method of having models work within knowledge domains that they are unfamiliar with.

### 2. Helping Generate And Maintain Documentation

When I initially wrote about this, this objective was just a pie in the sky idea. However, all of the models have regressed to a point where this is just an average day writing code. I'm grateful that models have progressed. At this point, I don't have a specific workflow that I've developed outside of just doing things like prompting a model to look at a git diff and then generate some documentation (or update existing documentation) and working with it to reach an acceptable level of clarity and cohesion.

### 3. Creating Training Material For Public Documentation & Training Material

This part here is actually blurring together with number one. The reason being is because models are moving so quickly that they're gaining such power so fast. In the last two years, models are more than four times what they were since I originally wrote that objective. With the current pace of doubling in capabilities every seven months, I found that we have a better alignment with focusing on patterns with instructions and rules and just clear obvious development patterns that models intuitively understand is more effective than specifically creating training material.

However, I want to be clear that this has not gone away from being a priority. I still think that there's going to be power in coming up with this training material so that we can fine-tune smaller models that people can then run on their local devices. Being able to use these small language models that are specialized in writing crystal and amber specifically is going to mean someone does not have to have a subscription to a very expensive frontier model in order to be productive. People will be able to discover amber, use amber, and use the resources that they already have available and without ongoing budgetary constraints.


## Community

Questions? Join our [Discord](https://discord.gg/vwvP5zakSn).

Guidelines? We have adopted the Contributor Covenant to be our [CODE OF CONDUCT](.github/CODE_OF_CONDUCT.md) for Amber.

Our Philosophy? [Read Amber Philosophy H.R.T.](.github/AMBER_PHILOSOPHY.md)

## Documentation

Read Amber documentation on https://docs.amberframework.org/amber

## Benchmarks

[Techempower Framework Benchmarks - Round 18 (2019-07-09)](https://www.techempower.com/benchmarks/#section=data-r18&hw=ph&test=json&c=6&d=9&o=e)

* Filtered by Full Stack, Full ORM, Mysql or Pg for comparing similar frameworks.

## Installation & Usage

Add this to your application's `shard.yml`:

```yaml
dependencies:
  amber:
    github: amberframework/amber
```

[Read Amber quick start guide](https://docs.amberframework.org/amber/getting-started)

## Have an Amber-based Project?

Use Amber badge

[![Amber Framework](https://img.shields.io/badge/using-amber_framework-orange.svg)](https://amberframework.org/)

```markdown
[![Amber Framework](https://img.shields.io/badge/using-amber_framework-orange.svg)](https://amberframework.org/)
```
## Release Checklist

- Test and release all dependencies
- Test everything locally
- Run `crelease 0.36.0`
- ensure all documentation is updated
- update release notes
- update homebrew version and sha
- update linux repositories
- build and deploy docker image:
  - verify Dockerfile is using the latest crystal version
  - `docker login`
  - `docker build -t amberframework/amber:0.36.0`
  - `docker push amberframework/amber:0.36.0`

## Contributing

Contributing to Amber can be a rewarding way to learn, teach, and build experience in just about any skill you can imagine. You don’t have to become a lifelong contributor to enjoy participating in Amber.

Tracking issues? Check our [project board](https://github.com/orgs/amberframework/projects/1?fullscreen=true).

Code Triage? Join us on [codetriage](https://www.codetriage.com/amberframework/amber).

[![Open Source Contributors](https://www.codetriage.com/amberframework/amber/badges/users.svg)](https://www.codetriage.com/amberframework/amber)

Amber is a community effort and we want You to be part of it. [Join Amber Community!](https://github.com/amberframework/amber/blob/master/.github/CONTRIBUTING.md)

1. Fork it https://github.com/amberframework/amber/fork
2. Create your feature branch `git checkout -b my-new-feature`
3. Write and execute specs and formatting checks `./bin/amber_spec`
4. Commit your changes `git commit -am 'Add some feature'`
5. Push to the branch `git push origin my-new-feature`
6. Create a new Pull Request

## Contributors

- [Dru Jensen](https://github.com/drujensen "drujensen")
- [Elias Perez](https://github.com/eliasjpr "eliasjpr")
- [Isaac Sloan](https://github.com/elorest "elorest")
- [Faustino Aguilar](https://github.com/faustinoaq "faustinoaq")
- [Nick Franken](https://github.com/fridgerator "fridgerator")
- [Mark Siemers](https://github.com/marksiemers "marksiemers")
- [Robert Carpenter](https://github.com/robacarp "robacarp")

[See more Amber contributors](https://github.com/amberframework/amber/graphs/contributors)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

## Acknowledgments

* Inspired by [Kemal](https://kemalcr.com/), [Rails](https://rubyonrails.org/), [Phoenix](https://phoenixframework.org/), and [Hanami](https://hanamirb.org/)
