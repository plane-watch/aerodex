# == Schema Information
#
# Table name: routes
#
#  id                   :integer          not null, primary key
#  call_sign            :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  operator_id          :integer          not null
#  route_segments_count :integer          default(0), not null
#
# Indexes
#
#  index_routes_on_operator_id                (operator_id)
#  index_routes_on_operator_id_and_call_sign  (operator_id,call_sign) UNIQUE
#

# frozen_string_literal: true

require 'test_helper'

class RouteTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:american_airlines)
    @yssy = airports(:yssy)
    @klax = airports(:klax)
  end

  test 'call_sign is unique within an operator' do
    Route.create!(operator: @operator, call_sign: 'AA999')
    duplicate = Route.new(operator: @operator, call_sign: 'AA999')
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :call_sign
  end

  test 'call_sign may repeat across different operators' do
    Route.create!(operator: @operator, call_sign: 'AA995')
    other = Route.new(operator: operators(:united_airlines), call_sign: 'AA995')
    assert other.valid?
  end

  test 'accepts nested route_segments attributes and maintains order' do
    route = Route.create!(
      operator: @operator,
      call_sign: 'AA998',
      route_segments_attributes: [
        { airport_id: @yssy.id, order: 0 },
        { airport_id: @klax.id, order: 1 }
      ]
    )

    ordered = route.route_segments.order(:order)
    assert_equal [@yssy.id, @klax.id], ordered.map(&:airport_id)
    assert_equal 2, route.reload.route_segments_count
  end

  test 'replacing segments via nested attributes destroys the old ones' do
    route = Route.create!(
      operator: @operator,
      call_sign: 'AA997',
      route_segments_attributes: [{ airport_id: @yssy.id, order: 0 }]
    )
    old_segment_id = route.route_segments.first.id

    route.update!(
      route_segments_attributes: [
        { id: old_segment_id, _destroy: true },
        { airport_id: @klax.id, order: 0 }
      ]
    )

    assert_nil RouteSegment.find_by(id: old_segment_id)
    assert_equal [@klax.id], route.reload.route_segments.map(&:airport_id)
    assert_equal 1, route.route_segments_count
  end

  test 'destroying a route destroys its segments' do
    route = Route.create!(
      operator: @operator,
      call_sign: 'AA996',
      route_segments_attributes: [{ airport_id: @yssy.id, order: 0 }]
    )
    segment_id = route.route_segments.first.id

    route.destroy!

    assert_nil RouteSegment.find_by(id: segment_id)
  end
end
