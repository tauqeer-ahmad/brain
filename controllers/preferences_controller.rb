class Admin::PreferencesController < Admin::BaseController
  before_filter :get_preference, :only => [:show, :edit, :update, :destroy, :revisions]

  def index
    params[:search] ||= {}
    options = {:page => params[:page] || 1}
    params[:search][:term] = params[:q] if params[:q].present?
    @preferences = Preference.perform_search(params[:search], options)
    @facets = Preference.perform_search(params[:search], options, true)
    @categories  = Category.preferences.unique

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @preferences }
      format.text { render layout: false }
    end
  end

  def show
    @categories  = Category.preferences.unique
    @facets = Preference.perform_search({}, {}, true)
    if params[:snapshot_id].present?
      @snapshot = Snapshot.find(params[:snapshot_id])
      @post = @snapshot.snapshotable_instance
    end
  end

  def revisions
    @categories  = Category.preferences.unique
    @facets = Preference.perform_search({}, {}, true)
    @categories  = Category.preferences.unique
  end

  def new
    @preference = Preference.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @preference }
    end
  end

  def edit
    if params[:snapshot_id].present?
      @snapshot = Snapshot.find(params[:snapshot_id])
      @post = @snapshot.snapshotable_instance
    end
  end

  def create
    @preference = Preference.new(params[:preference])
    @preference.user = @preference.actor = current_user

    respond_to do |format|
      if @preference.save
        @preference.category.save if @preference.category
        format.html { redirect_to admin_preferences_path, notice: get_message("success") }
        format.json { render json: @preference, status: :created, location: @preference }
      else
        flash.now[:errors_stay] = @preference.errors.full_messages.to_sentence
        format.html { render action: "new" }
        format.json { render json: @preference.errors, status: :unprocessable_entity }
      end
    end
  end

  def update
    @preference.attributes = params[:preference]
    @preference.user = @preference.actor = current_user
    respond_to do |format|
      if @preference.save
        @preference.category.save if @preference.category
        format.html { redirect_to edit_admin_preference_path(@preference), notice: get_message("success") }
        format.json { head :no_content }
      else
        flash.now[:errors_stay] = @preference.errors.full_messages.to_sentence
        format.html { render action: "edit" }
        format.json { render json: @preference.errors, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @preference.destroy

    redirect_to admin_preferences_url, notice: get_message("success")
  end


  protected

  def get_preference
    @preference = Preference.find_by_name(params[:id])

    unless @preference
      @preference = Preference.find_by_id(params[:id])
      return redirect_to(params.merge(:id => @preference.name)) if @preference
    end

    unless @preference
      flash[:error] = "Preference #{params[:id]} does not exist!"
      redirect_to admin_preferences_path
    end
  end

  def can_access?
    return true if current_user.can_access_preferences?
    super
  end

end
