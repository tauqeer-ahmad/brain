class OrdersController < ApplicationController
  before_filter :authenticate_user!, :only => [:free]

  def free
    @product = Product.find(params[:id])

    unless @product.free?
      flash[:error] = "You think you're smart enough to play with the parameters?"
      return redirect_to(:back)
    end

    log_event("Request Buy Free", :product_id => params[:id])

    @carts = @product.carts.purchased.find_all_by_user_id(current_user.id)

    if @carts.present?
      flash[:warning] = "You already have this product in your order(s) #{@carts.collect {|cart| cart.order.id}.to_sentence}"
      return redirect_to(:controller => 'account', :anchor => ['buyer', "order-tab-#{@carts.last.order.id}"].join('&'))
    end

    @cart = Cart.create :user => current_user, :purchased_at => Time.now.utc, :products => [@product]
    @order = @cart.build_order
    @order.ip_address = request.remote_ip
    @order.user = current_user
    @order.state = 'completed'
    @order.save :validate => false
    @product.got_purchased
    @product.notify_free_purchase(current_user)

    respond_to do |format|
      format.html do
        flash[:success] = "Success! Your products are available for download now."
        redirect_to :controller => 'account', :anchor => 'buyer'
      end
      format.js
    end
  end

  def paypal_dg_blank
    render :layout => 'blank'
  end

  def paypal_dg_cancel
    render :layout => false
  end

  def paypal_dg
    response = PAYPAL_DG_GATEWAY.setup_purchase(current_cart.price_in_cents, options_for_dg_payment)

    if response.success?
      redirect_to PAYPAL_DG_GATEWAY.redirect_url_for(response.token)
    else
      flash.now[:error_stay] = response.message
      render :layout => 'blank'
    end
  end

  def paypal_dg_success
    @order = current_cart.build_order
    @order.ip_address = request.remote_ip
    @order.user = current_user
    @order.cart.user = current_user
    @order.cart.save
    @order.express_token = params[:token]

    if @order.save
      @success = @order.purchase
      if @success
        flash[:success] = "Your products are available for download now!"
        sign_in @order.user unless user_signed_in?
      else
        flash[:error] = @order.transactions.last.message
      end
    else
      flash[:error] = @order.errors.full_messages.to_sentence
    end

    render :layout => false
  end

  def express
    response = EXPRESS_GATEWAY.setup_purchase(current_cart.build_order.price_in_cents, options_for_express_payment)

    if response.success?
      redirect_to EXPRESS_GATEWAY.redirect_url_for(response.token)
    else
      flash[:error_stay] = response.message
      redirect_to cart_path
    end
  end

  def new
    @order = current_cart.build_order
    @order.user = current_user
    @order.express_token = params[:token]
  end

  def create
    @order = current_cart.build_order
    @order.ip_address = request.remote_ip
    @order.user = current_user
    @order.cart.user = current_user
    @order.cart.save
    @order.attributes = params[:order]

    if @order.save
      @success = @order.purchase
      if @success
        flash[:success] = "Your products are available for download now!"
        sign_in @order.user unless user_signed_in?
        return redirect_to(:controller => 'account', :anchor => 'buyer')
      else
        flash.now[:error] = @order.transactions.last.message
      end
    else
      flash.now[:error] = @order.errors.full_messages.to_sentence
    end

    render :action => 'new'
  end

  protected

  def options_for_express_payment
    items = []
    current_cart.products.each_with_index do |product, index|
      items << ({ :name => product.title,
                  :number => index+1,
                  :quantity => "1",
                  :amount   => product.price_in_cents,
                  :description => "#{Product} #{product.id}",#product.description,
                  :url         => product.url(request.host_with_port),
                  :category => "Digital",
                  })
    end

    {
      :ip                => request.remote_ip,
      :return_url        => new_order_url,
      :cancel_return_url => cart_url,
      :description       => "Buying #{current_cart.products.collect(&:title).to_sentence}",
    }
  end

  def options_for_dg_payment
    items = []
    current_cart.products.each_with_index do |product, index|
      items << ({ :name => product.title,
                  :number => index+1,
                  :quantity => "1",
                  :amount   => product.price_in_cents,
                  :description => "#{Product} #{product.id}",#product.description,
                  :url         => product.url(request.host_with_port),
                  :category => "Digital",
                  })
    end

    {
      :ip                => request.remote_ip,
      :return_url        => paypal_dg_success_orders_url,
      :cancel_return_url => paypal_dg_cancel_orders_url,
      :description       => "Buying #{current_cart.products.collect(&:title).to_sentence}",
      :items             => items,
    }
  end
end
