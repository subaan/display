class Organization::TeamMembersController < ApplicationController
  before_filter :authorize_admin, :except => [:index]
  before_filter :find_team

  def index
    render :json => {:users => @team.users.all, :groups => @team.groups.all}
  end

  def create
    error = nil
    username = params[:username]
    group_name = params[:group]
    if username.present?
      @member = User.where(:username => username).first
      if @member
        if @team.users.exists?(@member)
          error = "User #{username} is already a member of team '#{@team.name}'."
        else
          @team.users << @member
        end
      else
        error = "Unknown user: #{username}"
      end
    elsif group_name.present?
      @member = Group.where(:name => group_name).first
      if @member
        if @team.groups.exists?(@member)
          error = "Group #{group_name} is already added to team '#{@team.name}'."
        else
          @team.groups << @member
        end
      else
        error = "Unknown user: #{group_name}"
      end
    else
      error = 'No member identifier specified.'
    end

    OrganizationMailer.added_to_team(@member, @team, current_user).deliver if error.blank? && @member.is_a?(User)

    respond_to do |format|
      format.js { flash[:error] = error if error }
      format.json { error ? render_json_ci_response(false, @team, [error]) : index }
    end
  end

  def destroy
    error = nil
    member_id = params[:id]
    if params[:type] == 'group'
      @member = @team.groups.where((member_id =~ /\D/ ? 'groups.name' : 'groups.id') => member_id).first
      @team.groups.delete @member if @member

    else
      @member = @team.users.where((member_id =~ /\D/ ? 'users.username' : 'users.id') => member_id).first
      @team.users.delete @member if @member
    end
    error = "Team member '#{member_id}' not found" unless @member

    OrganizationMailer.removed_from_team(@member, @team, current_user).deliver if error.blank? && @member.is_a?(User)

    respond_to do |format|
      format.js do
        flash[:error] = error if error
        render :action => :create
      end

      format.json { error ? render_json_ci_response(false, @member, [error]) : index }
    end
  end


  private

  def find_team
    team_qualifier = params[:team_id]
    if team_qualifier.present?
      @team = team_qualifier  =~ /\D/ ? current_user.organization.teams.where(:name => team_qualifier).first : current_user.organization.teams.find(team_qualifier)
    end
  end
end
