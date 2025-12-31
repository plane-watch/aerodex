# frozen_string_literal: true

require 'test_helper'

class RunwaySurfaceNormaliserTest < ActiveSupport::TestCase
  # Asphalt variations
  test 'normalises ASPH to asphalt' do
    assert_equal :asphalt, RunwaySurfaceNormaliser.normalise('ASPH')
  end

  test 'normalises ASP to asphalt' do
    assert_equal :asphalt, RunwaySurfaceNormaliser.normalise('ASP')
  end

  test 'normalises Asphalt (mixed case) to asphalt' do
    assert_equal :asphalt, RunwaySurfaceNormaliser.normalise('Asphalt')
  end

  test 'normalises asphalt (lowercase) to asphalt' do
    assert_equal :asphalt, RunwaySurfaceNormaliser.normalise('asphalt')
  end

  test 'normalises ASPH-F to asphalt' do
    assert_equal :asphalt, RunwaySurfaceNormaliser.normalise('ASPH-F')
  end

  # Asphalt/Concrete combinations
  test 'normalises ASPH-CONC to asphalt_concrete' do
    assert_equal :asphalt_concrete, RunwaySurfaceNormaliser.normalise('ASPH-CONC')
  end

  test 'normalises CONC/ASPH to asphalt_concrete' do
    assert_equal :asphalt_concrete, RunwaySurfaceNormaliser.normalise('CONC/ASPH')
  end

  test 'normalises ASP/CON to asphalt_concrete' do
    assert_equal :asphalt_concrete, RunwaySurfaceNormaliser.normalise('ASP/CON')
  end

  test 'normalises Asphalt/Concrete to asphalt_concrete' do
    assert_equal :asphalt_concrete, RunwaySurfaceNormaliser.normalise('Asphalt/Concrete')
  end

  # Concrete variations
  test 'normalises CONC to concrete' do
    assert_equal :concrete, RunwaySurfaceNormaliser.normalise('CONC')
  end

  test 'normalises CON to concrete' do
    assert_equal :concrete, RunwaySurfaceNormaliser.normalise('CON')
  end

  test 'normalises Concrete to concrete' do
    assert_equal :concrete, RunwaySurfaceNormaliser.normalise('Concrete')
  end

  test 'normalises CONCRETE to concrete' do
    assert_equal :concrete, RunwaySurfaceNormaliser.normalise('CONCRETE')
  end

  test 'normalises Cement to concrete' do
    assert_equal :concrete, RunwaySurfaceNormaliser.normalise('Cement')
  end

  # Grass variations
  test 'normalises GRASS to grass' do
    assert_equal :grass, RunwaySurfaceNormaliser.normalise('GRASS')
  end

  test 'normalises GRS to grass' do
    assert_equal :grass, RunwaySurfaceNormaliser.normalise('GRS')
  end

  test 'normalises Grassed Brown Clay to grass' do
    assert_equal :grass, RunwaySurfaceNormaliser.normalise('Grassed Brown Clay')
  end

  test 'normalises grass (lowercase) to grass' do
    assert_equal :grass, RunwaySurfaceNormaliser.normalise('grass')
  end

  test 'normalises herbe to grass' do
    assert_equal :grass, RunwaySurfaceNormaliser.normalise('Grass - Herbe')
  end

  test 'normalises SOD to grass' do
    assert_equal :grass, RunwaySurfaceNormaliser.normalise('SOD')
  end

  # Turf (distinct from grass)
  test 'normalises TURF to turf' do
    assert_equal :turf, RunwaySurfaceNormaliser.normalise('TURF')
  end

  test 'normalises TURF-G to turf' do
    assert_equal :turf, RunwaySurfaceNormaliser.normalise('TURF-G')
  end

  test 'normalises Turf/Dirt to turf' do
    assert_equal :turf, RunwaySurfaceNormaliser.normalise('Turf/Dirt')
  end

  # Gravel variations
  test 'normalises GRAVEL to gravel' do
    assert_equal :gravel, RunwaySurfaceNormaliser.normalise('GRAVEL')
  end

  test 'normalises GRVL to gravel' do
    assert_equal :gravel, RunwaySurfaceNormaliser.normalise('GRVL')
  end

  test 'normalises GVL to gravel' do
    assert_equal :gravel, RunwaySurfaceNormaliser.normalise('GVL')
  end

  test 'normalises crushed rock to gravel' do
    assert_equal :gravel, RunwaySurfaceNormaliser.normalise('CRUSHED ROCK')
  end

  # Dirt/Earth variations
  test 'normalises DIRT to dirt' do
    assert_equal :dirt, RunwaySurfaceNormaliser.normalise('DIRT')
  end

  test 'normalises Earth to dirt' do
    assert_equal :dirt, RunwaySurfaceNormaliser.normalise('Earth')
  end

  test 'normalises Ground to dirt' do
    assert_equal :dirt, RunwaySurfaceNormaliser.normalise('Ground')
  end

  test 'normalises Loam to dirt' do
    assert_equal :dirt, RunwaySurfaceNormaliser.normalise('Loam')
  end

  # Sand
  test 'normalises SAND to sand' do
    assert_equal :sand, RunwaySurfaceNormaliser.normalise('SAND')
  end

  test 'normalises SAN to sand' do
    assert_equal :sand, RunwaySurfaceNormaliser.normalise('SAN')
  end

  # Water (seaplane bases)
  test 'normalises WATER to water' do
    assert_equal :water, RunwaySurfaceNormaliser.normalise('WATER')
  end

  test 'normalises Water to water' do
    assert_equal :water, RunwaySurfaceNormaliser.normalise('Water')
  end

  # Ice
  test 'normalises ICE to ice' do
    assert_equal :ice, RunwaySurfaceNormaliser.normalise('ICE')
  end

  # Snow
  test 'normalises SNOW to snow' do
    assert_equal :snow, RunwaySurfaceNormaliser.normalise('SNOW')
  end

  test 'normalises SNO to snow' do
    assert_equal :snow, RunwaySurfaceNormaliser.normalise('SNO')
  end

  # Coral
  test 'normalises CORAL to coral' do
    assert_equal :coral, RunwaySurfaceNormaliser.normalise('CORAL')
  end

  test 'normalises Coral sand to coral' do
    assert_equal :coral, RunwaySurfaceNormaliser.normalise('Coral sand')
  end

  # Clay
  test 'normalises CLAY to clay' do
    assert_equal :clay, RunwaySurfaceNormaliser.normalise('CLAY')
  end

  test 'normalises CLA to clay' do
    assert_equal :clay, RunwaySurfaceNormaliser.normalise('CLA')
  end

  # Bituminous/Tar
  test 'normalises BITUM to bituminous' do
    assert_equal :bituminous, RunwaySurfaceNormaliser.normalise('BITUM')
  end

  test 'normalises Tarmac to bituminous' do
    assert_equal :bituminous, RunwaySurfaceNormaliser.normalise('Tarmac')
  end

  test 'normalises TAR to bituminous' do
    assert_equal :bituminous, RunwaySurfaceNormaliser.normalise('TAR')
  end

  test 'normalises Macadam to bituminous' do
    assert_equal :bituminous, RunwaySurfaceNormaliser.normalise('Macadam')
  end

  # Metal (PSP, etc.)
  test 'normalises PSP to metal' do
    assert_equal :metal, RunwaySurfaceNormaliser.normalise('PSP')
  end

  test 'normalises Metal to metal' do
    assert_equal :metal, RunwaySurfaceNormaliser.normalise('Metal')
  end

  test 'normalises MTAL to metal' do
    assert_equal :metal, RunwaySurfaceNormaliser.normalise('MTAL')
  end

  # Paved (generic)
  test 'normalises PAVED to paved' do
    assert_equal :paved, RunwaySurfaceNormaliser.normalise('PAVED')
  end

  test 'normalises Sealed to paved' do
    assert_equal :paved, RunwaySurfaceNormaliser.normalise('Sealed')
  end

  # Unpaved (generic)
  test 'normalises Unpaved to unpaved' do
    assert_equal :unpaved, RunwaySurfaceNormaliser.normalise('Unpaved')
  end

  test 'normalises not paved to unpaved' do
    assert_equal :unpaved, RunwaySurfaceNormaliser.normalise('Not paved')
  end

  # Unknown/Edge cases
  test 'normalises nil to unknown' do
    assert_equal :unknown, RunwaySurfaceNormaliser.normalise(nil)
  end

  test 'normalises empty string to unknown' do
    assert_equal :unknown, RunwaySurfaceNormaliser.normalise('')
  end

  test 'normalises unrecognised value to unknown' do
    assert_equal :unknown, RunwaySurfaceNormaliser.normalise('Some Random Junk')
  end

  test 'normalises X to unknown' do
    assert_equal :unknown, RunwaySurfaceNormaliser.normalise('X')
  end

  test 'normalises UNK to unknown' do
    assert_equal :unknown, RunwaySurfaceNormaliser.normalise('UNK')
  end

  # Display name tests
  test 'display_name returns Asphalt for asphalt surfaces' do
    assert_equal 'Asphalt', RunwaySurfaceNormaliser.display_name('ASPH')
  end

  test 'display_name returns Asphalt/Concrete for combined surfaces' do
    assert_equal 'Asphalt/Concrete', RunwaySurfaceNormaliser.display_name('ASPH-CONC')
  end

  test 'display_name returns Unknown for nil' do
    assert_equal 'Unknown', RunwaySurfaceNormaliser.display_name(nil)
  end

  test 'display_name returns Unknown for unrecognised value' do
    assert_equal 'Unknown', RunwaySurfaceNormaliser.display_name('Random')
  end

  # normalise_with_display tests
  test 'normalise_with_display returns hash with type and display_name' do
    result = RunwaySurfaceNormaliser.normalise_with_display('ASPH')

    assert_equal :asphalt, result[:type]
    assert_equal 'Asphalt', result[:display_name]
  end

  # batch_normalise tests
  test 'batch_normalise returns hash mapping raw values to canonical types' do
    surfaces = %w[ASPH CONC GRASS ASPH]
    result = RunwaySurfaceNormaliser.batch_normalise(surfaces)

    assert_equal :asphalt, result['ASPH']
    assert_equal :concrete, result['CONC']
    assert_equal :grass, result['GRASS']
    assert_equal 3, result.keys.length # Deduplicates
  end

  test 'batch_normalise handles nil values' do
    surfaces = ['ASPH', nil, 'CONC']
    result = RunwaySurfaceNormaliser.batch_normalise(surfaces)

    assert_equal 2, result.keys.length
    assert_not result.key?(nil)
  end
end