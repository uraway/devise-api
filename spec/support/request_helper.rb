# frozen_string_literal: true
module RequestHelper
  def user_token
    post '/v1/users', params: { user: { email: 'user@example.com', password: 'password' } }
    post '/v1/login', params: { email: 'user@example.com', password: 'password' }
    res = JSON.parse(response.body)
    res['access_token']
  end

  def get_user(path, params = {}, headers = {})
    headers['Authorization'] = user_token
    get path, params: params, headers: headers
  end
end
