require 'fileutils'
require 'google/protobuf'
load 'lib/proto/transit_pb.rb'

SIZES = [4.0, 1.0, 0.25]
LEVEL_BITS = 3
TILE_INDEX_BITS = 22
ID_INDEX_BITS = 21
LEVEL_MASK = (2**LEVEL_BITS) - 1
TILE_INDEX_MASK = (2**TILE_INDEX_BITS) - 1
ID_INDEX_MASK = (2**ID_INDEX_BITS) - 1
INVALID_ID = (ID_INDEX_MASK << (TILE_INDEX_BITS + LEVEL_BITS)) | (TILE_INDEX_MASK << LEVEL_BITS) | LEVEL_MASK

def int(value)
  # Simplify porting
  value.to_i
end

class UniqueIndex
  def initialize(start: 0)
    @index = start - 1
    @values = {}
  end

  def fetch(key)
    return nil if key.nil?
    @values.fetch(key)
  end

  def check(key)
    return nil if key.nil?
    @values[key] ||= (@index += 1)
  end

  def next(key)
    return nil if key.nil?
    @values[key] = (@index += 1)
  end
end

# https://github.com/valhalla/valhalla/blob/master/valhalla/midgard/encoded.h
class Shape7
  def self.encode(coordinates)
    output = []
    last_lat = 0
    last_lon = 0
    coordinates.each do |lat, lon|
      lat = (lat * 1e6).floor
      lon = (lon * 1e6).floor
      # puts "last_lat: #{lat - last_lat} last_lon: #{lon - last_lon}"
      output += encode_int(lat - last_lat)
      output += encode_int(lon - last_lon)
      last_lat = lat
      last_lon = lon
    end
    output.join('')
  end

  def self.decode(value)
    last_lat = 0
    last_lon = 0
    decode_ints(value).each_slice(2).map do |lat,lon|
      lat /= 1e6
      lon /= 1e6
      last_lat += lat
      last_lon += lon
      [last_lat, last_lon]
    end
  end

  private

  def self.encode_int(number)
    ret = []
    number = number < 0 ? ~(number << 1) : number << 1
    while (number > 0x7f) do
      # Take 7 bits
      nextValue = (0x80 | (number & 0x7f))
      ret << nextValue.chr
      number >>= 7
    end
    # Last 7 bits
    ret << (number & 0x7f).chr
    ret
  end

  def self.decode_ints(value)
    ret = []
    index = 0
    while (index < value.size) do
      shift = 0
      result = 0
      nextValue = value[index].ord
      while (nextValue > 0x7f) do
        # Next 7 bits
        result |= (nextValue & 0x7f) << shift
        shift += 7
        index += 1
        nextValue = value[index].ord
      end
      # Last 7 bits
      result |= (nextValue & 0x7f) << shift
      # One's complement if msb is 1
      result = (result & 1 == 1 ? ~result : result) >> 1
      # Add to output
      ret << result
      index += 1
    end
    ret
  end
end

class Tile
  attr_reader :level, :tile, :message
  def initialize(level, tile, data: nil)
    @level = level
    @tile = tile
    @index = {}
    @message = load(data)
  end

  def load(data)
    if data
      message = decode(data)
    else
      message = Valhalla::Mjolnir::Transit.new
    end
    message.nodes.each { |node| @index[GraphID.new(value: node.graphid).index] = node.graphid }
    message
  end

  def decode(data)
    Valhalla::Mjolnir::Transit.decode(data)
  end

  def encode
    Valhalla::Mjolnir::Transit.encode(@message)
  end

  def next_index
    (@index.keys.max || 0) + 1
  end

  def bbox
    GraphID.level_tile_to_bbox(@level, @tile)
  end

end

class TileSet
  def initialize(path)
    @path = path
    @tiles = {}
  end

  def get_tile(level, tile)
    @tiles[[level, tile]] ||= read_tile(level, tile)
  end

  def get_tile_by_lll(level, lat, lon)
    get_tile_by_graphid(GraphID.new(level: level, lat: lat, lon: lon))
  end

  def get_tile_by_graphid(graphid)
    get_tile(graphid.level, graphid.tile)
  end

  def write_tile(tile)
    fn = tile_path(tile.level, tile.tile)
    FileUtils.mkdir_p(File.dirname(fn))
    File.open(fn, 'wb') do |f|
      f.write(tile.encode)
    end
  end

  private

  def tile_path(level, tile)
    s = tile.to_s.rjust(9, "0")
    File.join(@path, level.to_s, s[0...3], s[3...6], s[6...9]+".pbf")
  end

  def read_tile(level, tile)
    fn = tile_path(level, tile)
    if File.exists?(fn)
      Tile.new(level, tile, data: File.read(fn))
    else
      Tile.new(level, tile)
    end
  end

end

class GraphID
  attr_accessor :value
  def initialize(value: nil, **kwargs)
    @value = value || (self.class.make_id(**kwargs))
  end

  def self.make_id(level: 0, tile: 0, index: 0, lat: nil, lon: nil)
    if lat && lon
      tile = lll_to_tile(level, lat, lon)
    end
    level | tile << LEVEL_BITS | index << (LEVEL_BITS + TILE_INDEX_BITS)
  end

  def self.lll_to_tile(tile_level, lat, lon)
    size = SIZES[tile_level]
    width = int(360 / size)
    int((lat + 90) / size) * width + int((lon + 180 ) / size)
  end

  def self.level_tile_to_bbox(level, tile)
    size = SIZES[level]
    width = int(360 / size)
    height = int(180 / size)
    ymin = int(tile / width) * size - 90
    xmin = (tile % width) * size - 180
    xmax = xmin + size
    ymax = ymin + size
    [xmin, ymin, xmax, ymax]
  end

  def self.bbox_to_level_tiles(ymin, xmin, ymax, xmax)
    # if this is crossing the anti meridian split it up and combine
    left, bottom, right, top = ymin, xmin, ymax, xmax
    if left > right
      east = tiles_for_bbox(left, bottom, 180.0, top)
      west = tiles_for_bbox(-180.0, bottom, right, top)
      return east + west
    end
    #move these so we can compute percentages
    left += 180
    right += 180
    bottom += 90
    top += 90
    tiles = []
    SIZES.each_index do |level|
      size = SIZES[level]
      (int(left/size)..(int(right/size))).each do |x|
        (int(bottom/size)..(int(top/size))).each do |y|
          tile = int(y * (360.0 / size) + x)
          tiles << [level, tile]
        end
      end
    end
    tiles
  end

  def bbox
    self.class.level_tile_to_bbox(level, tile)
  end

  def level
    @value & LEVEL_MASK
  end

  def tile
    (@value >> LEVEL_BITS )& TILE_INDEX_MASK
  end

  def index
    (@value >> LEVEL_BITS + TILE_INDEX_BITS) & ID_INDEX_MASK
  end
end
