require 'open_food_web/queries_product_distribution'

class ApplicationController < ActionController::Base
  protect_from_forgery

  before_filter :load_data_for_menu
  before_filter :load_data_for_sidebar

  private
  def load_data_for_menu
    @cms_site = Cms::Site.where(:identifier => 'open-food-web').first
  end

  def load_data_for_sidebar
    @suppliers = Enterprise.is_primary_producer
    @order_cycles = OrderCycle.active
    @distributors = OpenFoodWeb::QueriesProductDistribution.active_distributors
  end

  # All render calls within the block will be performed with the specified format
  # Useful for rendering html within a JSON response, particularly if the specified
  # template or partial then goes on to render further partials without specifying
  # their format.
  def with_format(format, &block)
    old_formats = formats
    self.formats = [format]
    block.call
    self.formats = old_formats
    nil
  end

end
