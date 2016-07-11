<!--
{"id":"6653812171404925684","title":"Rails5 API + devise でユーザーの認証と追加機能を実装した API を作成する","categories":["Rails API"],"draft":false}
-->

# Rails5 API + devise でユーザーの認証と追加機能を実装した API を作成する

## 目標

Rails v5.0.0 から追加された`api`オプションを使い, ユーザーの追加と認証機能を実装したベーシックな Rails API を作る.

## rails new

まずはプロジェクトを作成します

```bash
$ rails new devise-api --api --skip-bundle
```

`Gemfile` に次の `gem` を追加し, `bundle install`

```ruby
gem 'devise'
gem 'active_model_serializers'
```

## devise

devise を立ち上げます

```bash
$ rails generate devise:install
      create  config/initializers/devise.rb
      create  config/locales/devise.en.yml
```

`User` モデルを作成します

```bash
$ rails generate devise User
      invoke  active_record
      create    db/migrate/20160710134334_devise_create_users.rb
      create    app/models/user.rb
      invoke    test_unit
      create      test/models/user_test.rb
      create      test/fixtures/users.yml
      insert    app/models/user.rb
       route  devise_for :users
```

## token 認証

`access_token` カラムをユーザーテーブルに追加します

```bash
$ rails generate migration add_access_token_to_user
```

```ruby
class AddAccessTokenToUser < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :access_token, :string
  end
end
```

サンプルとしてトークンの生成にユーザーの`id`とトークン自身を使用します. `devise` モジュールの説明については[こちら](https://github.com/plataformatec/devise)

```ruby
# app/models/user.rb
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  # :recoverable, :rememberable, :trackable
  devise :database_authenticatable, :registerable, :validatable

  after_create :update_access_token!

  validates :email, presence: true

  def update_access_token!
    self.access_token = "#{self.id}:#{Devise.friendly_token}"
    save
  end

end
```

ユーザー認証のロジックは `application_controller` に配置されます

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  include AbstractController::Translation

  before_action :authenticate_user_from_token!

  respond_to :json

  ##
  # User Authentication
  # Authenticates the user with OAuth2 Resource Owner Password Credentials
  def authenticate_user_from_token!
    auth_token = request.headers['Authorization']

    if auth_token
      authenticate_with_auth_token auth_token
    else
      authenticate_error
    end
  end

  private

  def authenticate_with_auth_token auth_token
    unless auth_token.include?(':')
      authenticate_error
      return
    end

    user_id = auth_token.split(':').first
    user = User.where(id: user_id).first

    if user && Devise.secure_compare(user.access_token, auth_token)
      # User can access
      sign_in user, store: false
    else
      authenticate_error
    end
  end

  ##
  # Authentication Failure
  # Renders a 401 error
  def authenticate_error
    # User's token is either invalid or not in the right format
    render json: { error: t('unauthorized') }, status: 401 # Authentication
  end
end
```

`sessions_controller` に対して `login` ルートを割り当てます.

```ruby
# config/routes.rb
Rails.application.routes.draw do
  devise_for :user, only: []

  namespace :v1, defaults: { format: :json } do
    resource :login, only: [:create], controller: :sessions
  end
end
```

`sessions_controller` は次のようにログインリクエストを処理します.

```ruby
# app/controllers/v1/sessions_controller.rb
module V1
  class SessionsController < ApplicationController
    skip_before_action :authenticate_user_from_token!

    # POST /v1/login
    def create
      @user = User.find_for_database_authentication(email: params[:email])
      return invalid_email unless @user

      if @user.valid_password?(params[:password])
        sign_in :user, @user
        render json: @user, serializer: SessionSerializer, root: nil
      else
        invalid_password
      end
    end

    private

    def invalid_email
      warden.custom_failure!
      render json: { error: t('invalid_email') }
    end

    def invalid_password
      warden.custom_failure!
      render json: { error: t('invalid_password') }
    end
  end
end
```

`session_serializer.rb` によって, オブジェクトを整形します.

```ruby
# app/serializers/v1/session_serializer.rb
module V1
  class SessionSerializer < ActiveModel::Serializer

    attributes :email, :token_type, :user_id, :access_token

    def user_id
      object.id
    end

    def token_type
      'Bearer'
    end

  end
end
```

## ユーザーのサインアップ

次にユーザーの登録プロセスを実装します.

```ruby
# app/controllers/v1/users_controller.rb
module V1
  class UsersController < ApplicationController
    skip_before_action :authenticate_user_from_token!, only: [:create]

    # POST
    # Create an user
    def create
      @user = User.new user_params

      if @user.save!
        render json: @user, serializer: V1::SessionSerializer, root: nil
      else
        render json: { error: t('user_create_error') }, status: :unprocessable_entity
      end
    end

    private

    def user_params
      params.require(:user).permit(:email, :password)
    end
  end
end
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  devise_for :user, only: []

  namespace :v1, defaults: { format: :json } do
    resource :login, only: [:create], controller: :sessions
    resource :users, only: [:create]
  end
end
```

## 動作確認

データベースをマイグレーション(`rake db:create db:migrate`)して, サーバーを立ち上げ(`rails server`)ます.
コンソールからユーザーを作成, ログインをテストします.

```bash
$ curl localhost:3000/v1/users --data "email=user@example.com&password=password"
{"email":"user@example.com","token_type":"Bearer","user_id":1,"access_token":"1:C3bUyza9y1AX-s_H2q5r"}
```

```bash
$ curl localhost:3000/v1/login --data "email=user@example.com&password=password"
{"email":"user@example.com","token_type":"Bearer","user_id":1,"access_token":"1:C3bUyza9y1AX-s_H2q5r"}
```

より強固なものにするために `spec` 等を書きましょう.

## CORS

フロントエンドのアプリケーションをこの API に対しリクエストを送る形で作成するのですが, 通常の設定では別ドメインからのリクエストは拒否されてしまいます.

これを解決するには Cross-Origin Resource Sharing ([CORS](http://en.wikipedia.org/wiki/Cross-origin_resource_sharing)) を[rack-cors](https://github.com/cyu/rack-cors) を使ってクロスドメイン通信を許可します.

```ruby
gem 'rack-cors'
```

設定を `config/application.rb` に追加します:

```ruby
config.middleware.insert_before 'Rack::Runtime', 'Rack::Cors' do
  allow do
    origins '*'
    resource '*',
             headers: :any,
             methods: [:get, :put, :post, :patch, :delete, :options]
  end
end
```

この設定のままではすべてのドメインからのリクエストを許可しているので, セキュリティ面は脆弱です.
