class OrganizationController < ApplicationController
  include ::CostSummary, ::NotificationSummary

  before_filter :authorize_admin, :only => [:update, :announcement]
  skip_before_filter :check_organization, :only => [:public_profile, :request_access, :lookup]

  def show
    respond_to do  |format|
      format.html do
        @entities = Cms::Relation.all(:params => { :ciId => current_user.organization.cms_id}).group_by { |r| r.relationName }
        @clouds = Cms::Ci.all(:params => {:nsPath => clouds_ns_path, :ciClassName => 'account.Cloud'})
        @assemblies = locate_assemblies.sort_by { |o| o.created_timestamp }
      end

      format.json {render :json => current_user.organization.ci}
    end
  end

  def edit
    @organization = current_user.organization
    respond_to do  |format|
      format.html
      format.json {render :json => @organization.as_json.merge(:ci => @organization.ci)}
    end
  end

  def update
    @organization = current_user.organization
    org_ci = @organization.ci
    ci_attrs = params[:organization].delete(:ci)
    org_attrs = strong_params
    org_ci.meta.attributes[:mdAttributes].each do |attr|
      attr_name = attr.attributeName
      if @organization.attributes.include?(attr_name)
        org_attrs[attr_name] = ci_attrs['ciAttributes'][attr_name] || org_ci.ciAttributes.attributes[attr_name]
      end
    end
    ok = @organization.update_attributes(org_attrs)
    if ok
      begin
        Cms::Ci.headers.delete('X-Cms-Scope')
        ok = execute(org_ci, :update_attributes, ci_attrs)
      ensure
        Cms::Ci.headers['X-Cms-Scope'] = "/#{current_user.organization.name}"
      end
    end

    flash[:error] = 'Failed to update organization.' unless ok
    respond_to do  |format|
      format.js
      format.json {render :json => @organization.as_json.merge(:ci => org_ci)}
    end
  end

  def deployments
    @deployment_state = params[:deployment_state] || 'active'
    @deployments = Cms::Deployment.all(:params => {:nsPath => organization_ns_path,
                                                   :recursive => true,
                                                   :deploymentState => @deployment_state})
    unless is_admin? || has_org_scope?
      @deployments = @deployments.select do |e|
        root, org, assembly = e.nsPath.split('/')
        current_user.has_transition?(assembly)
      end
    end

    respond_to do |format|
      format.js
      format.json {render :json => @deployments}
    end
  end

  def procedures
    @procedures = Cms::Procedure.all(:params => {:nsPath    => organization_ns_path,
                                                          :recursive => true,
                                                          :actions   => true,
                                                          :state     => 'active',
                                                          :limit     => 10000})
    unless is_admin? || has_org_scope?
      @procedures = @procedures.select do |e|
        root, org, assembly = e.nsPath.split('/')
        current_user.has_operations?(assembly)
      end
    end
  end

  def announcement
    if request.method == 'PUT'
      params[:announcements].each_pair do |org, a|
        org = current_user.organizations.where('organizations.name' => org).first
        org.update_attribute(:announcement, a) if org
      end
    end

    response = current_user.organizations.all.inject({}) { |m, org| m[org.name] = org.announcement; m }

    render :json => response
  end

  def public_profile
    org_name = params[:org_name]
    org = current_user.organizations.where('organizations.name' => org_name).first
    if org
      current_user.change_organization(org)
      redirect_to organization_path
      return
    end

    @organization = Organization.where(:name => org_name).first

    redirect_to not_found_path unless @organization
  end

  def request_access
    @organization = Organization.where(:name => params[:org_name]).first
    if @organization
      owner = @organization.ci.ciAttributes.owner
      if owner.present?
        recipients = [owner]
      else
        recipients = @organization.teams.where('teams.name' => Team::ADMINS).first.users.map(&:email)
      end
      OrganizationMailer.request_access(recipients, @organization, current_user, params[:message]).deliver
      flash[:notice] = 'Request sent.'
    end

    render :js => ''
  end

  def lookup
    name = "%#{params[:name]}%"
    render :json => Organization.where('name ILIKE ?', name).limit(10).map {|o| "#{o.name} #{o.full_name if o.full_name.present?}"}
  end


  private

  def strong_params
    params[:organization].permit(:name, :cms_id, :assemblies, :services, :catalogs, :announcement, :full_name)
  end
end
