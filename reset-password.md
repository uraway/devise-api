<!--
{"id":"10257846132695148307","title":"Rails 5 API + devise でパスワードのリセット","categories":["ruby"],"draft":"yes"}
-->

# Rails 5 API + devise でパスワードのリセット

前回: http://uraway.hatenablog.com/entry/2016/07/11/090206

Rails 5 API + devise の資料があんまりなかったのでメモ。前提として devise を使ったユーザー登録、ログイン機能を持っている API を作成しているとします。

また、 この一連のチュートリアルでは [`devise_token_auth`](https://github.com/lynndylanhurley/devise_token_auth) は使用しません。

ソースコードは [GitHub](https://github.com/uraway/devise-api) にあるので、gem のバージョンやフォルダ構成などの参考にしてください。

- rails (5.2.2)
- devise (4.5.0)

## mailcatcher の導入

今回はメーラーを使用するので、[`mailcatcher`](https://rubygems.org/gems/mailcatcher/versions/0.6.1) を導入します。設定が楽なので Docker を使いますが必須ではないです。

```dockerfile
# Dockerfile
FROM ruby:2.5

ENV APP_ROOT /usr/src/devise-api

RUN apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs
# SQLite
RUN apt-get install sqlite3 libsqlite3-dev -y

RUN mkdir $APP_ROOT
WORKDIR $APP_ROOT
COPY Gemfile $APP_ROOT/Gemfile
COPY Gemfile.lock $APP_ROOT/Gemfile.lock
RUN bundle install
COPY . $APP_ROOT
```

```yml
# docker-compose.yml
version: "3"
services:
  app:
    build: ./
    command: bundle exec rails s -p 3000 -b '0.0.0.0'
    volumes:
      - .:/usr/src/devise-api
    ports:
      - "3000:3000"
    tty: true
    stdin_open: true
  mailcatcher:
    image: schickling/mailcatcher
    ports:
      - "1080:1080"
      - "1025:1025"
```

mailcatcher の設定を書き加えます。Docker を使用している場合はホスト名にコンテナ名を使用することができます。

```ruby
# config/environments/development.rb
  config.action_mailer.smtp_settings = {
    address: 'mailcatcher',
    port: 1025
  }
```

`docker-compose up` して、http://localhost:1080 にアクセスしましょう。

![](https://cdn-ak.f.st-hatena.com/images/fotolife/u/uraway/20190102/20190102170331.png)

## パスワードリセットメールを送信する

devise の `recoverable` をオンにします。

```ruby
# app/models/user.rb

class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :validatable, :recoverable
```

`passwords_controller.rb`を新たに作り、ルートを割り当てます。[`send_reset_password_instructions`](https://www.rubydoc.info/github/plataformatec/devise/Devise/Models/Recoverable/ClassMethods#send_reset_password_instructions-instance_method) は devise が用意したメソッドで、ユーザーにパスワードリセットメールを送信します。

このとき注意したいのがレスポンスに関してで、リクエストパラメータのメールアドレスを持つユーザーが存在しないとき、その有無のエラーメッセージを返すのではなく、有無にかかわらず同じメッセージを返したほうが良いでしょう。悪意のある送信者に、そのメールアドレスのユーザーが登録されているかを知られることを防ぐことができます。

```ruby
# app/controllers/passwords_controller.rb
module V1
  class PasswordsController < ApplicationController
    skip_before_action :authenticate_user_from_token!, only: [:create]

    def create
      user = User.find_by(email: create_params[:email])
      user&.send_reset_password_instructions
      render json: {}
    end

    private

    def create_params
      params.require(:user).permit(:email)
    end
  end
end
```

```ruby
# config/routes.rb
    ...
    resource :passwords, only: [:create]
    ...
```

`send_reset_password_instructions`で送信されるメールテンプレートは、[`app/views/devise/mailers/reset_password_instructions.html.erb`](https://github.com/plataformatec/devise/blob/master/app/views/devise/mailer/reset_password_instructions.html.erb) にて次のように定義されています。

```html
<p>Hello <%= @resource.email %>!</p>

<p>
  Someone has requested a link to change your password. You can do this through
  the link below.
</p>

<p>
  <%= link_to 'Change my password', edit_password_url(@resource,
  reset_password_token: @token) %>
</p>

<p>If you didn't request this, please ignore this email.</p>
<p>
  Your password won't change until you access the link above and create a new
  one.
</p>
```

`edit_password_url` を token 付きのフロントエンドのパスワードリセットページ URL に変えます。

```html
<p>
  <%= link_to 'Change my password', "https://yourfrontend.com?token=#{@token}"%>
</p>
```

mailcatcher を使ってメールが送信されることを確かめてみましょう。メールアドレスが `user@example.com` のユーザーが存在するとします。

```
$ curl -X POST -H "Content-Type: application/json" localhost:3000/v1/passwords --data '{"user": { "email": "user@example.com" } }'

{}
```

http://localhost:1080 にアクセスして、メールの内容を確認してみます。

![](https://cdn-ak.f.st-hatena.com/images/fotolife/u/uraway/20190102/20190102014020.png)

Change my password をクリックすると、次のようなリセットパスワードトークン付きの URL が取得できます: `https://yourfrontend.com/?token=8XAXEzhFxCnn6zidyb9B`

## トークンを受け取ってパスワードリセットする

リセットパスワードトークンは暗号化されてデータベースに保存されるため、リセットパスワードトークンからユーザーを見つけ出し、パスワードをリセットするには、devise によって追加されたクラスメソッド `User.reset_password_by_token` を使用します。このメソッドは `reset_password_token`/`password`/`password_confirmation`を受け取ります。

リセットパスワードトークンと新しいパスワードを受け取り、パスワードを更新するコントローラーを定義しましょう。

```ruby
# app/controllers/passwords_controller.rb
module V1
  class PasswordsController < ApplicationController
    skip_before_action :authenticate_user_from_token!, only: [:create, :update]

    ...

    def update
      user = User.reset_password_by_token(update_params)
      render json: user, status: :ok, serializer: V1::UserSerializer
    end

    private

    ...

    def update_params
      params.require(:user).permit(:password, :password_confirmation, :reset_password_token)
    end
  end
end
```

```ruby
# config/routes.rb
    ...
    resource :passwords, only: [:create, :update]
    ...
```

パスワードのリセットを試してみましょう。先程送信したメールのクエリにあるトークンと、新しく設定したいパスワードをデータに PUT リクエストを実行します。

```
$ curl -X PUT -H "Content-Type: application/json" localhost:3000/v1/passwords --data '{"user": {"password": "newpass" ,"reset_password_token": "nysLs8eSLHHZm3eNw2fg"}}'

{"email":"user@example.com"}
```

パスワードが新しく設定できたかどうかも確認してみましょう。

```
$ curl -X POST -H "Content-Type: application/json" localhost:3000/v1/login --data '{"email": "user@example.com", "password": "newpass"}'

{"email":"user@example.com","token_type":"Bearer","user_id":1,"access_token":"1:yyjsJ_4oLN6k6z9_rZxE"}
```

## rspec を書いてみよう

リセットパスワードトークンはその期限が `config/initializers/devise.rb` にて定義されており、任意に変更できます。

```ruby
  # Time interval you can reset your password with a reset password key.
  # Don't put a too small interval or your users won't have the time to
  # change their passwords.
  config.reset_password_within = 6.hours
```

rspec を書いてみることで、トークンの期限が正しいかを確認しましょう。rspec 自体の導入方法については割愛します。

`Gemfile` に以下の 2 つの gem を追記して、`bundle install` します:

```
gem 'factory_bot_rails', '~> 4.0'
gem 'rspec-rails', '~> 3.8'
```

`TimeHelpers#travel_to` を使って、次のようにリセットパスワードトークンが正しく期限切れになるかどうか確認することができます。

```ruby
# spec/requests/passwords_spec.rb
require 'rails_helper'

include ActiveSupport::Testing::TimeHelpers

  ...

  describe 'PUT /v1/passwords' do
    before do
      @raw, enc = Devise.token_generator.generate(User, :reset_password_token)
      user.reset_password_token   = enc
      user.reset_password_sent_at = Time.now.utc
      user.save(validate: false)
    end

    context 'when params have a new password and a valid token' do
      it 'resets password' do
        travel_to(Time.current + 5.hours)
        params = { user: { password: 'newpass', password_confirmation: 'newpass', reset_password_token: @raw } }
        put '/v1/passwords', params: params
        expect(User.first.valid_password? 'newpass').to eq true
      end
    end

    context 'when params have invalid token' do
      it 'does not reset password with expired token' do
        travel_to(Time.current + 7.hours)
        params = { user: { password: 'newpass', password_confirmation: 'newpass', reset_password_token: @raw } }
        put '/v1/passwords', params: params
        expect(User.first.valid_password? 'newpass').to eq false
      end
    end

    ...

  end
```
