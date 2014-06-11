require 'ap'
require 'mechanize'
require 'msgpack'
require 'nokogiri'

class Scrapper
	URI_NGNT = 'http://bravefrontier.nogamenotalk.com'
	URI_WIKIA = 'http://bravefrontierglobal.wikia.com/wiki'

	attr_reader :unit_table, :index

	# unit_table = {
	# 	id => {
	# 		:name
	# 		:element
	# 		:rarity
	# 		:max_level
	# 		:cost
	# 		:evolution => {
	# 			:pre,
	# 			:post,
	# 			:requirement => { :zel, :unit => { :id => :count } }
	# 		}
	# 		:attacks => {
	# 			:normal,
	# 			:bb,
	# 			:sbb
	# 		}
	# 		:bb_type
	# 	}
	# }

	# index = {
	# 	:name => { :name => :id }
	# 	:element => { :element => [] }
	# 	:rarity => { :rarity => [] }
	# 	:cost => { :cost => [] }
	# 	:bb_type => { :bb_type => [] }
	# 	:usage => { :id => { :used_by => :count } }
	# }

	def initialize
		@agent = Mechanize.new
		@links = Hash.new
		@unit_table = Hash.new
	end

	def debug *id
		id.each do |r|
			ap r
		end
	end

	def scrap
		generate_ngnt_links
	end

	def to_json
	end

	def to_s
		ap @unit_table
		ap @links
	end

	private
		def generate_ngnt_links
			body = Nokogiri::HTML(@agent.get(URI_NGNT).body)
			scrap_ngnt_links_on URI_NGNT
			body.xpath('//*/ul[1]/dd/a/@href')[1..-1].each do |nav|
				scrap_ngnt_links_on URI.join(URI_NGNT, nav.text)
			end

			link_file = File.join(File.dirname(__FILE__), 'links.mp')
			File.open(link_file, 'wb') { |f| f.write @links.to_msgpack}
		end

		def scrap_ngnt_links_on _url
			body = Nokogiri::HTML(@agent.get(_url).body)
			body.xpath('//*/table[@class="units"]/tbody/tr').each do |row|
				col = row.xpath('td').map { |x| x.text }
				row.attributes['class'].text =~ /unit (\w+)/i
				element = $1

				@unit_table[col[0].to_i] = {
					element: 		element,
					rarity: 		col[2].to_i,
					name: 			col[3],
					max_level: 		col[4].to_i,
					cost: 			col[5].to_i,
					bb_type: 		nil,
					evolution: 		nil,
					attacks: 		nil,
				}

				@links[col[0].to_i] = row.xpath('td[4]/a/@href').text
			end
		end
end