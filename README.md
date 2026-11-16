# rails-openapi-annotations

[English](#english) | [Español](#español)

---

# English

## Overview

`rails-openapi-annotations` is a Ruby gem that generates an OpenAPI 3.0.3 document from annotated Rails controller actions and the application's registered Rails routes.

It is designed for Rails APIs backed by ActiveRecord. The gem scans controller annotations, resolves the associated model, builds request and response schemas from the model's database columns and validations, applies optional application-level overrides, and writes the resulting document to `openapi/openapi.yaml`.

The generator only documents controller actions that have an `@openapi` annotation.

## Features

- Generate an OpenAPI 3.0.3 YAML document from Rails routes and controller annotations.
- Infer model schemas from ActiveRecord columns and validations.
- Infer path parameters from route placeholders such as `{id}`.
- Generate common CRUD operations for `index`, `show`, `create`, `update`, and `destroy` actions.
- Add operation summaries, descriptions, tags, and operation IDs.
- Declare authentication schemes only when configured.
- Support custom operation builders for controller-specific operations.
- Override generated request bodies and responses per controller action.
- Register reusable schemas under `components.schemas` and reference them with `$ref`.
- Configure the successful-response wrapper, if the API uses one.

## Requirements

- A Ruby on Rails application.
- ActiveRecord-backed models and a configured database schema.
- A Ruby version compatible with the Rails version used by the application.

The gem currently relies on ActiveRecord metadata to infer model schemas. APIs that do not use ActiveRecord or a database-backed model layer are outside the current scope.

## Installation

### Install from GitHub

Add the gem to the application's `Gemfile`:

```ruby
gem "rails-openapi-annotations",
    git: "https://github.com/jgonmor/rails-openapi-annotations.git",
    tag: "v0.1.0",
    require: "rails/openapi/annotations"
```

Then install the dependency:

```bash
bundle install
```

Use a published Git tag such as `v0.1.0` to pin the application to a known revision. The tag must exist in the repository before Bundler can resolve it.

### Use a local checkout during gem development

When developing the gem and the Rails application side by side, a local path dependency can be used temporarily:

```ruby
gem "rails-openapi-annotations",
    path: "../rails-openapi-annotations",
    require: "rails/openapi/annotations"
```

Replace the `path:` entry with the Git dependency before deploying or sharing the application.

## Generate the OpenAPI document

The gem registers the following Rake task through its Railtie:

```bash
bundle exec rake openapi:from_controllers
```

The generated file is:

```text
openapi/openapi.yaml
```

The task loads the Rails environment, scans the registered Rails routes, finds annotated actions, and generates the document. Routes without an `@openapi` annotation are skipped.

### Document-level environment variables

The following environment variables customize the generated document:

| Variable | Default | Description |
|---|---|---|
| `OPENAPI_TITLE` | `Rails API` | Document title. |
| `OPENAPI_VERSION` | `1.0.0` | API/document version. |
| `OPENAPI_SERVER_URL` | `http://localhost:3000` | Server URL included in the OpenAPI document. |

For example:

```bash
OPENAPI_TITLE="Inventory API" \
OPENAPI_VERSION="1.2.0" \
OPENAPI_SERVER_URL="https://api.example.com" \
bundle exec rake openapi:from_controllers
```

## Controller annotations

Add an `@openapi` comment immediately above the action it documents. The annotation uses space-separated `key:"value"` fields.

### Basic annotation

```ruby
class Api::V1::InventoryItemsController < ApplicationController
  # @openapi summary:"List inventory items" description:"Returns all inventory items"
  def index
    render json: InventoryItem.all
  end
end
```

The generator uses the annotation to document the action and matches it with the corresponding Rails route.

### Supported annotation fields

| Field | Example | Purpose |
|---|---|---|
| `summary` | `summary:"List inventory items"` | Short operation summary. |
| `description` | `description:"Returns all inventory items"` | Longer operation description. |
| `auth` | `auth:"true"` | Adds the configured security requirement to the operation. |
| `model` | `model:"InventoryItem"` | Explicit ActiveRecord model name when it cannot be inferred from the controller name. |
| `request_fields` | `request_fields:"name,sku,quantity"` | Limits the generated request schema to the listed writable model columns. Separate names with commas. |

Fields are optional. `summary` and `description` are recommended for every documented action.

### Model inference and explicit model selection

By default, the generator infers the model from the last segment of the controller name, singularizes it, and resolves the corresponding ActiveRecord constant.

For example:

- `Api::V1::InventoryItemsController` resolves to `InventoryItem`.
- `Api::V1::TasksController` resolves to `Task`.

If inference is not suitable, specify the model in the annotation:

```ruby
# @openapi summary:"List archived records" model:"AuditRecord"
def index
  render json: AuditRecord.all
end
```

The specified constant must resolve to an ActiveRecord model.

### Restrict request fields

For create and update operations, `request_fields` can restrict the writable model columns included in the generated request body:

```ruby
# @openapi summary:"Create inventory item" request_fields:"name,sku,quantity"
def create
  # ...
end
```

The model schema builder still excludes system and sensitive columns from generated request fields. The exact request schema also depends on the model's database columns and validations.

### Authentication annotation

Mark an operation as requiring authentication with `auth:"true"`:

```ruby
# @openapi summary:"List private records" auth:"true"
def index
  # ...
end
```

This does not select an authentication mechanism by itself. Configure `security_schemes` and `security_requirement` in the initializer (see [Configuration](#configuration)). If an annotated operation requires authentication but no security requirement is configured, generation raises an explicit error rather than adding an undefined security reference.

### Custom error annotations

An action can contain `@openapi error` comments to document additional error responses. Put the error annotation inside the action body:

```ruby
# @openapi summary:"Show inventory item"
def show
  # @openapi error status:"404" key:"error" example:"Inventory item not found" description:"The requested item does not exist"
  # ...
end
```

Supported attributes used by the error annotation:

| Attribute | Purpose |
|---|---|
| `status` | HTTP status code, for example `404` or `409`. |
| `key` | Response property name. Use `errors` for an array of error messages. |
| `example` | Example error message. |
| `description` | Optional response description. |

A regular `key` produces a string property in the response schema. The special key `errors` produces an array of strings. Error annotations are merged into the operation's responses by status code.

## Configuration

Create an initializer at:

```text
config/initializers/openapi_annotations.rb
```

The configuration is optional. With no initializer, the generator does not add an authentication scheme, does not require authentication, does not register custom schemas or builders, and does not wrap successful responses.

### Authentication schemes

For an API using JWT Bearer authentication:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.security_schemes = {
    "bearerAuth" => {
      "type" => "http",
      "scheme" => "bearer",
      "bearerFormat" => "JWT"
    }
  }

  config.security_requirement = [
    { "bearerAuth" => [] }
  ]
end
```

Then annotate protected actions with `auth:"true"`.

Other OpenAPI security schemes can be registered in the same way. For example, an API key in a header:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.security_schemes = {
    "apiKeyAuth" => {
      "type" => "apiKey",
      "in" => "header",
      "name" => "X-API-Key"
    }
  }

  config.security_requirement = [
    { "apiKeyAuth" => [] }
  ]
end
```

An API that does not use authentication can leave both settings empty/default and omit `auth:"true"` from its annotations.

### Successful-response wrapper

By default, successful model responses are documented without an additional wrapper. If the API returns a structure such as `{ "data": ... }`, configure the wrapper key:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.response_wrapper = "data"
end
```

The wrapper applies to the generated successful model responses for `index`, `show`, `create`, and `update`. It does not change the generated error response formats. Use `nil` (the default) for unwrapped arrays and objects.

### Reusable schemas

Register reusable schemas under `components.schemas`:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.schemas = {
    "InventoryItem" => {
      "type" => "object",
      "required" => %w[id name sku quantity],
      "properties" => {
        "id" => { "type" => "integer", "format" => "int64" },
        "name" => { "type" => "string" },
        "sku" => { "type" => "string" },
        "quantity" => { "type" => "integer" }
      }
    }
  }
end
```

Reference a registered schema from a response or request override with `$ref`:

```ruby
"schema" => {
  "$ref" => "#/components/schemas/InventoryItem"
}
```

### Per-operation response overrides

`response_overrides` is a hash keyed by `"controller#action"`. Each status code provided replaces the generated response for that status code. Other generated response status codes remain unchanged.

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.response_overrides = {
    "api/v1/inventory_items#index" => {
      "200" => {
        "description" => "Inventory items retrieved successfully",
        "content" => {
          "application/json" => {
            "schema" => {
              "type" => "array",
              "items" => {
                "$ref" => "#/components/schemas/InventoryItem"
              }
            }
          }
        }
      }
    }
  }
end
```

The key must match the Rails controller path and action name, not the URL path.

### Per-operation request-body overrides

`request_body_overrides` is also keyed by `"controller#action"`. The configured value replaces the generated `requestBody` for that operation:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.request_body_overrides = {
    "api/v1/inventory_items#create" => {
      "required" => true,
      "content" => {
        "application/json" => {
          "schema" => {
            "$ref" => "#/components/schemas/CreateInventoryItem"
          }
        }
      }
    }
  }
end
```

Register the referenced `CreateInventoryItem` schema under `config.schemas` as well.

### Custom operation builders

For controller actions that do not fit the standard model-backed CRUD behavior, register a custom builder for the controller:

```ruby
require "rails/openapi/annotations/builders/session_operation_builder"

Rails::Openapi::Annotations.configure do |config|
  config.register_operation_builder(
    "api/v1/sessions",
    Rails::Openapi::Annotations::Builders::SessionOperationBuilder.new
  )
end
```

A custom builder must respond to `build_operation` and accept the operation metadata, action, HTTP verb, route path, and model arguments:

```ruby
class MyOperationBuilder
  def build_operation(metadata, action, verb, path, model)
    {
      "summary" => metadata["summary"],
      "operationId" => "customOperation",
      "responses" => {
        "200" => { "description" => "OK" }
      }
    }
  end
end
```

Register it with `config.register_operation_builder("api/v1/custom", MyOperationBuilder.new)`. The custom builder is responsible for producing a valid OpenAPI Operation Object.

## How model schemas are inferred

For standard model-backed operations, the gem uses ActiveRecord metadata to build the default schemas.

- Response properties are inferred from model columns, excluding configured sensitive columns such as `password_digest` and `token_version`.
- Request properties are inferred from writable columns. Primary keys, STI columns, timestamps, and sensitive columns are excluded.
- Column types are mapped to common OpenAPI types and formats, including integer, number, boolean, date, date-time, time, JSON, binary, and UUID.
- Request required fields are inferred from presence validations and database null/default constraints.
- Password fields are added for models that contain `password_digest`.
- Path parameters are inferred from route placeholders and matching model columns when possible.

Use `request_fields`, `request_body_overrides`, `response_overrides`, or reusable schemas when the inferred contract does not match the API's actual JSON contract.

## CRUD action behavior

The standard operation builder recognizes these action/verb combinations:

| Controller action | HTTP verb | Generated operation |
|---|---|---|
| `index` | `GET` | Collection response. |
| `show` | `GET` | Single-resource response plus a `404` response. |
| `create` | `POST` | Request body, `201` response, and `422` validation response. |
| `update` | `PATCH` / `PUT` | Partial request body, `200` response, `404`, and `422` responses. |
| `destroy` | `DELETE` | `204` response and `404` response. |

The generator only creates operations for annotated actions that also have a matching registered Rails route.

## Development and tests

Clone the repository and install its dependencies:

```bash
git clone https://github.com/jgonmor/rails-openapi-annotations.git
cd rails-openapi-annotations
bundle install
```

Run the complete default check (style and tests):

```bash
bundle exec rake
```

Run the checks separately:

```bash
bundle exec rake standard
bundle exec rake test
```

## Current scope

- The generator targets Rails APIs with ActiveRecord-backed models.
- The default model inference and request/response schema generation use ActiveRecord metadata.
- Custom builders, schemas, request bodies, responses, and security definitions can be supplied by the application.
- The output format is OpenAPI 3.0.3 YAML.

Support for non-ActiveRecord persistence layers or APIs without database-backed models may be considered separately in the future; it is not part of the current scope.

## License

See the repository's `LICENSE` file.

---

# Español

## Descripción

`rails-openapi-annotations` es una gema Ruby que genera un documento OpenAPI 3.0.3 a partir de anotaciones en las acciones de los controladores Rails y de las rutas registradas por la aplicación.

Está diseñada para APIs Rails respaldadas por ActiveRecord. La gema analiza las anotaciones de los controladores, resuelve el modelo asociado, construye esquemas de petición y respuesta a partir de las columnas y validaciones del modelo, aplica las personalizaciones opcionales de la aplicación y escribe el documento resultante en `openapi/openapi.yaml`.

El generador solo documenta las acciones de los controladores que tienen una anotación `@openapi`.

## Funcionalidades

- Generación de un documento YAML OpenAPI 3.0.3 a partir de las rutas Rails y las anotaciones de los controladores.
- Inferencia de esquemas de modelos mediante columnas y validaciones de ActiveRecord.
- Inferencia de parámetros de ruta a partir de placeholders como `{id}`.
- Generación de operaciones CRUD habituales para las acciones `index`, `show`, `create`, `update` y `destroy`.
- Definición de resúmenes, descripciones, etiquetas e identificadores de operación.
- Declaración de esquemas de autenticación únicamente cuando se configuran.
- Soporte para builders de operaciones personalizados por controlador.
- Sustitución de cuerpos de petición y respuestas generados para acciones concretas.
- Registro de esquemas reutilizables en `components.schemas` y referencias mediante `$ref`.
- Configuración del envoltorio de las respuestas exitosas, si la API utiliza uno.

## Requisitos

- Una aplicación Ruby on Rails.
- Modelos respaldados por ActiveRecord y un esquema de base de datos configurado.
- Una versión de Ruby compatible con la versión de Rails utilizada por la aplicación.

Actualmente, la gema utiliza metadatos de ActiveRecord para inferir los esquemas de los modelos. Las APIs que no utilizan ActiveRecord o una capa de modelos respaldada por base de datos quedan fuera del alcance actual.

## Instalación

### Instalar desde GitHub

Añade la gema al `Gemfile` de la aplicación:

```ruby
gem "rails-openapi-annotations",
    git: "https://github.com/jgonmor/rails-openapi-annotations.git",
    tag: "v0.1.0",
    require: "rails/openapi/annotations"
```

Después instala la dependencia:

```bash
bundle install
```

Se recomienda fijar la dependencia a una etiqueta Git publicada, como `v0.1.0`, para que la aplicación utilice una revisión conocida. La etiqueta debe existir en el repositorio antes de que Bundler pueda resolverla.

### Usar una copia local durante el desarrollo de la gema

Mientras se desarrolla la gema y la aplicación Rails en paralelo, se puede utilizar temporalmente una dependencia por ruta local:

```ruby
gem "rails-openapi-annotations",
    path: "../rails-openapi-annotations",
    require: "rails/openapi/annotations"
```

Antes de desplegar o compartir la aplicación, sustituye `path:` por la dependencia Git.

## Generar el documento OpenAPI

La gema registra la siguiente tarea Rake mediante su Railtie:

```bash
bundle exec rake openapi:from_controllers
```

El archivo generado es:

```text
openapi/openapi.yaml
```

La tarea carga el entorno Rails, analiza las rutas registradas, localiza las acciones anotadas y genera el documento. Las rutas cuyas acciones no tienen una anotación `@openapi` se omiten.

### Variables de entorno del documento

Las siguientes variables permiten personalizar la información general del documento:

| Variable | Valor predeterminado | Descripción |
|---|---|---|
| `OPENAPI_TITLE` | `Rails API` | Título del documento. |
| `OPENAPI_VERSION` | `1.0.0` | Versión de la API/documento. |
| `OPENAPI_SERVER_URL` | `http://localhost:3000` | URL del servidor incluida en el documento OpenAPI. |

Ejemplo:

```bash
OPENAPI_TITLE="Inventory API" \
OPENAPI_VERSION="1.2.0" \
OPENAPI_SERVER_URL="https://api.example.com" \
bundle exec rake openapi:from_controllers
```

## Anotaciones en los controladores

Añade un comentario `@openapi` inmediatamente encima de la acción que quieres documentar. La anotación utiliza campos separados por espacios con el formato `clave:"valor"`.

### Anotación básica

```ruby
class Api::V1::InventoryItemsController < ApplicationController
  # @openapi summary:"List inventory items" description:"Returns all inventory items"
  def index
    render json: InventoryItem.all
  end
end
```

El generador utiliza la anotación para documentar la acción y la relaciona con la ruta Rails correspondiente.

### Campos de anotación disponibles

| Campo | Ejemplo | Función |
|---|---|---|
| `summary` | `summary:"List inventory items"` | Resumen breve de la operación. |
| `description` | `description:"Returns all inventory items"` | Descripción más extensa de la operación. |
| `auth` | `auth:"true"` | Añade a la operación el requisito de seguridad configurado. |
| `model` | `model:"InventoryItem"` | Nombre explícito del modelo ActiveRecord cuando no puede inferirse del controlador. |
| `request_fields` | `request_fields:"name,sku,quantity"` | Limita el esquema de petición generado a las columnas escribibles indicadas. Separa los nombres con comas. |

Todos los campos son opcionales. Se recomienda incluir `summary` y `description` en cada acción documentada.

### Inferencia y selección explícita del modelo

Por defecto, el generador obtiene el modelo a partir del último segmento del nombre del controlador, lo singulariza y busca la constante ActiveRecord correspondiente.

Por ejemplo:

- `Api::V1::InventoryItemsController` se resuelve como `InventoryItem`.
- `Api::V1::TasksController` se resuelve como `Task`.

Si la inferencia no es adecuada, indica el modelo en la anotación:

```ruby
# @openapi summary:"List archived records" model:"AuditRecord"
def index
  render json: AuditRecord.all
end
```

La constante indicada debe corresponder a un modelo ActiveRecord.

### Limitar los campos de petición

En las operaciones de creación y actualización, `request_fields` permite limitar las columnas escribibles del modelo que se incluyen en el cuerpo de petición generado:

```ruby
# @openapi summary:"Create inventory item" request_fields:"name,sku,quantity"
def create
  # ...
end
```

El constructor de esquemas sigue excluyendo las columnas de sistema y sensibles de los campos de petición. El esquema exacto también depende de las columnas y validaciones del modelo.

### Anotación de autenticación

Marca una operación como protegida mediante `auth:"true"`:

```ruby
# @openapi summary:"List private records" auth:"true"
def index
  # ...
end
```

La anotación no selecciona por sí misma el mecanismo de autenticación. Debes configurar `security_schemes` y `security_requirement` en el inicializador (consulta [Configuración](#configuración)). Si una operación exige autenticación y no existe un requisito de seguridad configurado, la generación lanza un error explícito en lugar de crear una referencia de seguridad indefinida.

### Anotaciones de errores personalizados

Una acción puede contener comentarios `@openapi error` para documentar respuestas de error adicionales. Coloca la anotación de error dentro del cuerpo de la acción:

```ruby
# @openapi summary:"Show inventory item"
def show
  # @openapi error status:"404" key:"error" example:"Inventory item not found" description:"The requested item does not exist"
  # ...
end
```

Atributos utilizados por la anotación de error:

| Atributo | Función |
|---|---|
| `status` | Código HTTP, por ejemplo `404` o `409`. |
| `key` | Nombre de la propiedad de la respuesta. Utiliza `errors` para una lista de mensajes. |
| `example` | Mensaje de ejemplo del error. |
| `description` | Descripción opcional de la respuesta. |

Un valor normal de `key` genera una propiedad de tipo string en el esquema de respuesta. La clave especial `errors` genera un array de strings. Las anotaciones de error se incorporan a las respuestas de la operación según su código HTTP.

## Configuración

Crea un inicializador en:

```text
config/initializers/openapi_annotations.rb
```

La configuración es opcional. Sin inicializador, el generador no añade esquemas de autenticación, no exige autenticación, no registra esquemas o builders personalizados y no añade envoltorios a las respuestas exitosas.

### Esquemas de autenticación

Para una API que utilice autenticación JWT Bearer:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.security_schemes = {
    "bearerAuth" => {
      "type" => "http",
      "scheme" => "bearer",
      "bearerFormat" => "JWT"
    }
  }

  config.security_requirement = [
    { "bearerAuth" => [] }
  ]
end
```

Después, marca las acciones protegidas con `auth:"true"`.

También se pueden registrar otros esquemas de seguridad OpenAPI. Por ejemplo, una API key enviada en una cabecera:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.security_schemes = {
    "apiKeyAuth" => {
      "type" => "apiKey",
      "in" => "header",
      "name" => "X-API-Key"
    }
  }

  config.security_requirement = [
    { "apiKeyAuth" => [] }
  ]
end
```

Una API que no utilice autenticación puede dejar ambos ajustes con sus valores predeterminados y no incluir `auth:"true"` en las anotaciones.

### Envoltorio de las respuestas exitosas

Por defecto, las respuestas exitosas de modelos se documentan sin un envoltorio adicional. Si la API devuelve una estructura como `{ "data": ... }`, configura la clave del envoltorio:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.response_wrapper = "data"
end
```

El envoltorio se aplica a las respuestas exitosas generadas para `index`, `show`, `create` y `update`. No modifica los formatos de las respuestas de error generadas. Utiliza `nil` (valor predeterminado) para arrays y objetos sin envoltorio.

### Esquemas reutilizables

Registra esquemas reutilizables en `components.schemas`:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.schemas = {
    "InventoryItem" => {
      "type" => "object",
      "required" => %w[id name sku quantity],
      "properties" => {
        "id" => { "type" => "integer", "format" => "int64" },
        "name" => { "type" => "string" },
        "sku" => { "type" => "string" },
        "quantity" => { "type" => "integer" }
      }
    }
  }
end
```

Utiliza `$ref` para hacer referencia a un esquema registrado desde una personalización de respuesta o petición:

```ruby
"schema" => {
  "$ref" => "#/components/schemas/InventoryItem"
}
```

### Personalizar respuestas por operación

`response_overrides` es un hash cuya clave tiene el formato `"controller#action"`. Cada código HTTP configurado sustituye la respuesta generada para ese mismo código. Los demás códigos generados se conservan.

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.response_overrides = {
    "api/v1/inventory_items#index" => {
      "200" => {
        "description" => "Inventory items retrieved successfully",
        "content" => {
          "application/json" => {
            "schema" => {
              "type" => "array",
              "items" => {
                "$ref" => "#/components/schemas/InventoryItem"
              }
            }
          }
        }
      }
    }
  }
end
```

La clave debe coincidir con la ruta del controlador Rails y el nombre de la acción, no con la URL.

### Personalizar cuerpos de petición por operación

`request_body_overrides` también utiliza claves `"controller#action"`. El valor configurado sustituye completamente el `requestBody` generado para esa operación:

```ruby
Rails::Openapi::Annotations.configure do |config|
  config.request_body_overrides = {
    "api/v1/inventory_items#create" => {
      "required" => true,
      "content" => {
        "application/json" => {
          "schema" => {
            "$ref" => "#/components/schemas/CreateInventoryItem"
          }
        }
      }
    }
  }
end
```

Registra también el esquema `CreateInventoryItem` dentro de `config.schemas`.

### Builders de operaciones personalizados

Para acciones que no encajan en el comportamiento CRUD estándar respaldado por modelos, registra un builder personalizado para el controlador:

```ruby
require "rails/openapi/annotations/builders/session_operation_builder"

Rails::Openapi::Annotations.configure do |config|
  config.register_operation_builder(
    "api/v1/sessions",
    Rails::Openapi::Annotations::Builders::SessionOperationBuilder.new
  )
end
```

Un builder personalizado debe responder a `build_operation` y aceptar los argumentos de metadatos de la operación, acción, verbo HTTP, ruta y modelo:

```ruby
class MyOperationBuilder
  def build_operation(metadata, action, verb, path, model)
    {
      "summary" => metadata["summary"],
      "operationId" => "customOperation",
      "responses" => {
        "200" => { "description" => "OK" }
      }
    }
  end
end
```

Regístralo mediante `config.register_operation_builder("api/v1/custom", MyOperationBuilder.new)`. El builder personalizado es responsable de producir un OpenAPI Operation Object válido.

## Cómo se infieren los esquemas de modelos

Para las operaciones estándar respaldadas por modelos, la gema utiliza metadatos de ActiveRecord para construir los esquemas predeterminados.

- Las propiedades de respuesta se infieren de las columnas del modelo, excluyendo columnas sensibles como `password_digest` y `token_version`.
- Las propiedades de petición se infieren de las columnas escribibles. Se excluyen las claves primarias, las columnas STI, las marcas de tiempo y las columnas sensibles.
- Los tipos de columna se traducen a tipos y formatos OpenAPI habituales, incluidos integer, number, boolean, date, date-time, time, JSON, binary y UUID.
- Los campos obligatorios de las peticiones se infieren de las validaciones de presencia y de las restricciones de nulabilidad y valores predeterminados de la base de datos.
- Se añaden campos de contraseña para modelos que contienen `password_digest`.
- Los parámetros de ruta se infieren de los placeholders de la ruta y, cuando es posible, de las columnas correspondientes del modelo.

Utiliza `request_fields`, `request_body_overrides`, `response_overrides` o esquemas reutilizables cuando el contrato inferido no coincida con el JSON real de la API.

## Comportamiento de las acciones CRUD

El builder estándar reconoce las siguientes combinaciones de acción y verbo HTTP:

| Acción del controlador | Verbo HTTP | Operación generada |
|---|---|---|
| `index` | `GET` | Respuesta de colección. |
| `show` | `GET` | Respuesta de un recurso y respuesta `404`. |
| `create` | `POST` | Cuerpo de petición, respuesta `201` y respuesta de validación `422`. |
| `update` | `PATCH` / `PUT` | Cuerpo de petición parcial y respuestas `200`, `404` y `422`. |
| `destroy` | `DELETE` | Respuesta `204` y respuesta `404`. |

El generador solo crea operaciones para acciones anotadas que también tengan una ruta Rails registrada.

## Desarrollo y tests

Clona el repositorio e instala sus dependencias:

```bash
git clone https://github.com/jgonmor/rails-openapi-annotations.git
cd rails-openapi-annotations
bundle install
```

Ejecuta la comprobación predeterminada completa (estilo y tests):

```bash
bundle exec rake
```

También puedes ejecutar las comprobaciones por separado:

```bash
bundle exec rake standard
bundle exec rake test
```

## Alcance actual

- El generador está orientado a APIs Rails con modelos respaldados por ActiveRecord.
- La inferencia predeterminada de modelos y la generación de esquemas de petición y respuesta utilizan metadatos de ActiveRecord.
- La aplicación puede proporcionar builders, esquemas, cuerpos de petición, respuestas y definiciones de seguridad personalizados.
- El formato de salida es YAML OpenAPI 3.0.3.

El soporte para capas de persistencia que no utilicen ActiveRecord o para APIs sin modelos respaldados por base de datos podrá considerarse en el futuro; no forma parte del alcance actual.

## Licencia

Consulta el archivo `LICENSE` del repositorio.
