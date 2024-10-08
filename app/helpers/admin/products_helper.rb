# frozen_string_literal: true

module Admin
  module ProductsHelper
    def product_image_form_path(product)
      if product.image.present?
        edit_admin_product_image_path(product.id, product.image.id)
      else
        new_admin_product_image_path(product.id)
      end
    end

    def prepare_new_variant(product)
      product.variants.build
    end

    def unit_value_with_description(variant)
      precised_unit_value = nil

      if variant.unit_value
        scaled_unit_value = variant.unit_value / (variant.product.variant_unit_scale || 1)
        precised_unit_value = number_with_precision(
          scaled_unit_value,
          precision: nil,
          strip_insignificant_zeros: true,
          significant: false,
        )
      end

      [precised_unit_value, variant.unit_description].compact_blank.join(" ")
    end

    def products_return_to_url(url_filters)
      if feature?(:admin_style_v3, spree_current_user)
        return session[:products_return_to_url] || admin_products_url
      end

      "#{admin_products_path}#{url_filters.empty? ? '' : "#?#{url_filters.to_query}"}"
    end
  end
end
