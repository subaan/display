class SessionsController < Devise::SessionsController
  skip_before_filter :check_username, :only => [:create]
  skip_before_filter :check_eula, :only => [:destroy, :create]
  skip_before_filter :check_organization, :only => [:destroy, :create]

  after_filter :session_username, :only => [:create]

  append_view_path(File.join(Rails.root, 'app', 'views', 'devise'))

  skip_after_filter :process_flash_messages, :only => [:new]

  def new
    if request.xhr?
      flash[:error] = params[:message].presence || I18n.t('devise.failure.timeout')
      render :js => "window.location = '#{new_user_session_url}?return_to=' + window.location.href"
    else
      return_to = params[:return_to]
      session['user_return_to'] = return_to if return_to.present?
      super
    end
  end

  def create
    super
    token = Devise.friendly_token
    session[:token] = token
    current_user.update_attribute(:session_token, token)
  end


  private

  def build_resource(hash = nil, options = {})
    super
    resource.email = params[:email].presence || params[:user].try {|u| u[:email]} if action_name == 'new'
  end

  def session_username
    session[:username] = current_user.username if current_user
  end
end
