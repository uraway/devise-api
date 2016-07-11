module V1
  class UsersController < ApplicationController
    skip_before_action :authenticate_user_from_token!, only: [:create]

    # POST /v1/users
    # Creates an user
    def create
      @user = User.new(email: params[:email], password: params[:password])
      if @user.save
        render json: @user, serializer: V1::SessionSerializer
      else
        render json: { error: t('user_create_error') }, status: :unprocessable_entity
      end
    end
  end
end
