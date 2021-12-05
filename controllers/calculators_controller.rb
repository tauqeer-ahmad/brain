class CalculatorsController < ApplicationController
  PER_PAGE = 10

  before_filter :get_calculator, :only => [:show, :result, :demo, :landing_page, :widget, :preview]
  before_filter :get_calculator_submission, :only => [:show, :demo, :preview]
  before_filter :set_meta_tags, :only => [:show, :demo]

  def index
    params[:search] ||= {}
    options      = {:page => params[:page] || 1, :per_page => Preference.get(:calculators_per_page).to_i}
    params[:search][:term] = params[:q] if params[:q].present?

    if demo_site?
      params[:search][:statuses] = Calculator::DEMO_STATUSES
    else
      params[:search].merge!(Calculator.default_search_options(:user => current_user))
    end

    @calculators = Calculator.perform_search(params[:search], options)
    @categories  = Category.calculators.visible.real.unique

    respond_to do |format|
      format.html
      format.js
      format.rss
      format.text do
        render :layout => false
      end
    end
  end

  def show
    get_calculator_submission
    get_calculator_notification
    @comments  = @calculator.root_comments.real.ordered.page(params[:page]).per(Comment::PER_PAGE)
    @unvoted_poll = @calculator.unvoted_poll(current_user)
    if params[:snapshot_id].present?
      @snapshot = Snapshot.find(params[:snapshot_id])
      @calculator = @snapshot.snapshotable_instance
    end

  end

  def demo
    show
    render :show
  end

  def preview
    show
    render :show, :layout => "naked"
  end

  def landing_page

  end

  def widget
    render :layout => 'widget'
  end

  def result
    @result = @calculator.computed_result(params[:calculator])
    render :partial => "result"
  end

  private

  def get_calculator
    @calculator = Calculator.find_by_sluggish_id(params[:id])

    unless @calculator
      @calculator = Calculator.find_by_id(params[:id])
      return redirect_to(params.merge(:id => @calculator.slug)) if @calculator
    end

    return render_404 unless @calculator

    redirect_to root_path, :notice => get_message("notice", "blank_calculator") unless @calculator
  end

  def get_calculator_submission
    @calculator_submission = @calculator.calculator_submissions.find_by_user_id(current_user.id) if user_signed_in?
    @calculator_submission = CalculatorSubmission.new if @calculator_submission.blank?
  end

  def get_calculator_notification
    if user_signed_in?
      email = current_user.email
      @calculator_notification = @calculator.calculator_notifications.find_by_email email
    end
    @calculator_notification ||= CalculatorNotification.new
  end

  def set_meta_tags
    @meta_title        = @calculator.title
    @meta_description  = @calculator.sub_title
    @meta_image        = @calculator.image.url
  end

end
