# CLAUDE.md

## Project Overview

Amber is a web application framework written in Crystal, inspired by Kemal, Rails, Phoenix and other popular application frameworks. It provides engineers with an 
efficient, cohesive, well-maintained web framework that embraces Crystal's language philosophies.
  
## Development Commands

### Building the Framework
```bash
# Install dependencies
shards install
```

### Running Tests

```bash
# Run all tests and checks (recommended)
./bin/amber_spec

# Individual test commands:
./bin/ameba                    # Run linter
crystal tool format --check    # Check code formatting
crystal spec                   # Run main test suite

# Run a single test file
crystal spec spec/amber/controller/base_spec.cr
```

### Development Workflow

```bash
# Format code
crystal tool format
```

## Architecture Overview

### Core Components

1. **CLI (`src/amber/cli/`)**: This part of the framework is hard deprecated and slated for total removal

2. **MVC Framework (`src/amber/`)**: 

     - **Controller** (`controller/`): Base controller with filters, rendering, redirects
     - **Router** (`router/`): HTTP routing with params, cookies, sessions, file handling
     - **Views**: Template support via Kilt (ECR, Slang, Liquid, etc.)

3. **Middleware System (`src/amber/pipes/`)**: HTTP request pipeline

     - CORS, CSRF protection, session management
     - Static file serving, error handling
     - Flash messages, logging

4. **WebSockets (`src/amber/websockets/`)**: Real-time communication

     - Channel-based architecture
     - Client socket management
     - Subscription system with adapter pattern

5. **Adapters (`src/amber/adapters/`)**: Pluggable backends

     - Session storage (Memory, Redis via conditional compilation)
     - PubSub (Memory, Redis via conditional compilation)
     - Factory pattern for runtime selection

6. **Environment & Configuration (`src/amber/environment/`)**:

     - YAML-based environment configs
     - Settings management
     - Logging configuration

7. **Key Design Patterns**:

     - **Adapter Pattern**: Session and PubSub systems use adapters for different backends
     - **Pipeline Pattern**: HTTP requests flow through configurable middleware pipes
     - **DSL Approach**: Router and server configuration use Crystal macros for clean syntax
     - **Convention over Configuration**: Similar to Rails, with sensible defaults

8. **Database Support**:

     - PostgreSQL, MySQL, SQLite3 drivers included
     - Micrate for database migrations
     - Works with Granite ORM (separate shard)

9. **Template Engines**:

     - ECR (Embedded Crystal)
     - Slang (Slim-like syntax)
     - Liquid
     - Mustache
     - Temel
     - Water

10. **Testing Approach**:

     - Uses Crystal's built-in `spec` framework
     - Ameba for linting
     - Comprehensive test coverage for all components
     - Separate test files for Granite ORM integration

11. **Current Development Branch**:

     - Working on `feature/remove-direct-redis-dependency` branch
     - Implementing adapter pattern to make Redis optional
     - Memory-based alternatives for session and PubSub
     - Maintaining backward compatibility

12. **Important Notes**:

     - Crystal version requirement: >= 1.0.0, < 2.0
     - Current stable version: 1.4.1
     - Main branch for PRs: `master`
     - Uses shards for dependency management
     - Docker support available - maybe. This hasn't been verified in a while.
