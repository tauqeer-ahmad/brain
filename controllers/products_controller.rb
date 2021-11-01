class ProductsController < ApplicationController
  before_filter :authenticate_user!, :only => [:new, :create, :edit, :update, :destroy, :remove_upload, :remove_image, :like, :like_comments, :add_upload, :reset, :add_image]
  before_filter :set_product, :only => [:show, :edit, :update, :destroy, :remove_upload, :remove_image, :like, :like_comments, :add_upload, :reset, :add_image]
  before_filter :product_editable!, :only => [:edit, :update, :destroy, :remove_upload, :remove_image, :add_upload, :reset, :add_image]

  def index
    @page_title = "Products List"

    params[:search] = HashWithIndifferentAccess.new(Rack::Utils.parse_nested_query(params[:_escaped_fragment_][1..-1]))[:search] if params[:_escaped_fragment_]
    params[:search] ||= {}
    params[:search][:page] ||= 1

    @products = Product.perform_search(params[:search])
    @next_params = params.merge(:partial => true)
    @next_params[:search] = @next_params[:search].merge(:page => @next_params[:search][:page].to_i+1)
    @tags = Tag.ordered.main.with_children.all

    return render(:partial => "products/list", :layout => false, :content_type => "text/html") if params[:partial]
    return render(:partial => "products/container", :layout => false, :content_type => "text/html") if params[:reload]
  end

  # GET /products/new
  # GET /products/new.json
  def new
    @product = Product.init.with_user(current_user.id).first || Product.new
    @product.user = current_user
    @product.force_save

    return redirect_to(edit_product_path(@product))

    @page_title = "Sell your product"
    @product = Product.new
    @tags = Tag.main.with_children.all

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @product }
    end
  end

  def show
    return redirect_to(@product.updated_product, :status => 301) if @product.updated_product && !params[:buyer]
    @page_title = @product.title
    @meta_description = @product.description.blank? ? @product.title : @product.description
    @meta_keywords = @product.keywords
    render :layout => 'blank' if params.has_key?(:naked)
  end

  # GET /products/1/edit
  def edit
    return redirect_to(edit_product_path(@product.duplicate)) if @product.in_cart?

    @page_title = "Sell your product"
    @product.original_priced!
    @product.valid? if flash[:error_stay]
    @tags = Tag.main.with_children.all
    flash.now[:warning_stay] = "It seems you don't have a Paypal account set. Please specify your Paypal account from My Account > #{self.class.helpers.link_to "Seller", account_path(:anchor => "seller")} section to receive instant payments." unless current_user.can_receieve_payment?
  end

  # POST /products
  # POST /products.json
  def create
    @page_title = "Sell your product"
    @product = Product.new(params[:product])
    @product.user = current_user

    if @product.valid?
      @product.force_save
      return product_success
    else
      flash[:error_stay] = @product.errors.full_messages
      @product.force_save
      redirect_to edit_product_path(@product)
    end
  end

  def update
    @page_title = "Sell your product"
    @product = @product.duplicate if @product.in_cart?
    @product.attributes = params[:product]
    if @product.valid?
      @product.created_at = Time.now.utc if @product.init?
      @product.force_save
      return product_success
    else
      flash[:error_stay] = @product.errors.full_messages.to_sentence
      @product.force_save
      redirect_to edit_product_path(@product)
    end
  end

  def reset
    @product.destroy
    return redirect_to(new_product_path)
  end

  def destroy
    @product.soft_destroy

    respond_to do |format|
      format.html do
        flash[:success] = "#{@product.title} successfully removed"
        return redirect_to(products_url) unless naked?
        render :layout => false
      end
      format.js
    end
  end

  def add_upload
    @uploads = params[:uploaded_files].to_a.collect do |file|
      @product.uploads.create :file => file
    end

    @message = @uploads.collect {|upload| upload.errors.full_messages.join(', ') if upload.new_record?}.compact.join(', ')
    flash.now[:error] = @message if @message.present?
    render :layout => false
  end

  def add_image
    @images = params[:uploaded_images].to_a.collect do |photo|
      @product.images.create :photo => photo
    end

    @message = @images.collect {|image| "#{image.photo_file_name} is not a valid image" unless image.valid?}.compact.join(', ')

    flash.now[:error] = @message if @message.present?
    render :layout => false
  end

  def remove_upload
    @upload  = Upload.find_by_id(params[:upload_id])
    @product.uploads.delete(@upload) if @upload
    respond_to do |format|
      format.js
    end
  end

  def remove_image
    @image  = Image.find(params[:image_id])
    @product.images.delete(@image)
    respond_to do |format|
      format.js
    end
  end

  def like_comments
    if @product.accessible_by?(current_user)
      @rating = @product.like_comment(current_user, params[:comment])
      flash.now[:success] = "Thank you for your comments on #{@product.title}"
    else
      flash.now[:error] = "Permission denied!"
    end

    respond_to do |format|
      format.js
    end
  end

  def like
    if @product.accessible_by?(current_user)
      @rating = @product.like(current_user, params[:like])
      flash.now[:success] = "You #{@rating.like? && 'liked' || 'disliked'} #{@product.title}"
    else
      flash.now[:error] = "Permission denied!"
    end

    respond_to do |format|
      format.js
    end
  end

  protected

  def set_product
    @product = Product.find_by_sluggish_id(params[:id])
    return head(404) if @product.blank?
    if @product.deleted?
      flash[:error] = "Product #{@product.title.inspect} has been deleted!"
      return redirect_to root_path, :status => 404
    end
  end

  def product_editable
    current_user.admin? || current_user.can_edit?(@product)
  end

  def product_editable!
    unless product_editable
      flash[:error] = "You dont have permission"
      return redirect_to(root_path)
    end
  end

  def product_success
    if @product.init?
      flash[:success] = 'Product was successfully created. It is now pending approval and will be displayed in the listings ASAP! Meanwhile, you can add more details to your product.'
      redirect_to( edit_product_path(@product, :optional => true))
    else
      flash[:success] = 'Product was successfully updated. It is now pending approval (again) and will be displayed in the listings ASAP!'
      redirect_to(@product)
    end

    @product.pend! if @product.init? || !current_user.admin?
  end
end
