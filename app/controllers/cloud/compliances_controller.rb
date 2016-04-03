class Cloud::CompliancesController < ApplicationController
  before_filter :find_cloud_and_compliance
  before_filter :authorize_write, :only => [:new, :create, :update, :destroy]

  def index
    load_compliances
    respond_to do |format|
      format.js { render :action => :index }
      format.json { render :json => @compliances }
    end
  end

  def show
    render_json_ci_response(@compliance.present?, @compliance)
  end

  def new
    compliance_class = validate_compliance_class
    return unless compliance_class

    ci_hash               = params[:cms_ci].presence || {}
    ci_hash[:ciClassName] = compliance_class
    ci_hash[:nsPath]      = cloud_ns_path(@cloud)
    @compliance           = Cms::Ci.build(:nsPath => cloud_ns_path(@cloud), :ciClassName => compliance_class)

    respond_to do |format|
      format.js
      format.json { render_json_ci_response(true, @compliance) }
    end
  end

  def create
    return unless validate_compliance_class

    @compliance = Cms::Ci.build(params[:cms_ci].merge(:nsPath => cloud_ns_path(@cloud)))
    relation    = Cms::Relation.build(:relationName => 'base.CompliesWith',
                                      :fromCiId     => @cloud.ciId,
                                      :nsPath       => cloud_ns_path(@cloud),
                                      :toCi         => @compliance)

    ok          = execute_nested(@compliance, relation, :save)
    @compliance = relation.toCi if ok

    respond_to do |format|
      format.js { ok ? index : render(:action => :new) }
      format.json { render_json_ci_response(ok, @compliance) }
    end
  end

  def edit
    respond_to do |format|
      format.js
      format.json { render_json_ci_response(true, @compliance) }
    end
  end

  def update
    ok = execute(@compliance, :update_attributes, params[:cms_ci])

    respond_to do |format|
      format.js { ok ? index : render(:action => :edit) }
      format.json { render_json_ci_response(ok, @compliance) }
    end
  end

  def destroy
    ok = execute(@compliance, :destroy)

    respond_to do |format|
      format.js do
        flash[:error] = 'Failed to delete service.' unless ok
        index
      end

      format.json { render_json_ci_response(ok, @compliance) }
    end
  end

  def available
    load_compliances
    render :json => @available_compliance_classes.map(&:className)
  end


  private

  def find_cloud_and_compliance
    @cloud      = locate_cloud(params[:cloud_id])
    compliance_id = params[:id]
    @compliance = Cms::Ci.locate(compliance_id, cloud_ns_path(@cloud)) if compliance_id.present?
  end

  def authorize_write
    unauthorized unless @cloud && has_cloud_compliance?(@cloud.ciId)
  end

  def load_compliances
    @compliances = Cms::Relation.all(:params => {:ciId         => @cloud.ciId,
                                                 :direction    => 'from',
                                                 :relationName => 'base.CompliesWith'}).map(&:toCi)

    existing = @compliances.to_map(&:ciClassName)
    @all_compliance_classes ||= Cms::CiMd.all(:params => {:package => 'cloud.compliance'})
    @available_compliance_classes = @all_compliance_classes.reject { |c| existing[c.className] }
  end

  def validate_compliance_class
    load_compliances

    error            = nil
    result = nil
    if @available_compliance_classes.blank?
      error = 'All compliance types already added.'
    else
      compliance_class = params[:compliance_class] || (params[:cms_ci] && params[:cms_ci][:ciClassName])
      result = compliance_class if compliance_class.present? && @available_compliance_classes.find { |c| c.className == compliance_class }
    end

    if result.blank?
      respond_to do |format|
        format.js
        format.json { render_json_ci_response(false, true, [error || 'Invalid compliance class.']) }
      end
    end

    return result
  end
end
