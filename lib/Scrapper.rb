require 'ap'
require 'mechanize'
require 'msgpack'
require 'nokogiri'

class Scrapper
	URI_NGNT = 'http://bravefrontier.nogamenotalk.com'
	URI_WIKIA = 'http://bravefrontierglobal.wikia.com/wiki'
	LINK_FILE = File.join(File.dirname(__FILE__), 'links.mp')

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
	# }

	def initialize
		@agent = Mechanize.new
		@links = Hash.new
		@unit_table = Hash.new
		@indices = {
			name: 		{},
			element: 	{},
			rarity: 	{},
			cost: 		{},
			bb_type: 	{},
		}
	end

	def debug *id
		begin
			@links = MessagePack.unpack(IO.binread LINK_FILE)
		rescue Errno::ENOENT
			generate_ngnt_links
		rescue
			raise
		end

		links = Hash.new
		id.each { |r| links[r] = @links[r] }
		parse_ngnt_pages links: links
	end

	def scrap
		generate_ngnt_links
		parse_ngnt_pages
		fetch_wikia_unit_hit_counts
		generate_unit_name_index		# must be called after wikia UHC fetch
										# since unit name is not populated
										# until this point
		merge_wikia_data(fetch_wikia_extra_categories)
		generate_full_indices
	end

	def to_json
	end

	def to_s
		ap @unit_table
		ap @indices
	end

	private
	def generate_unit_name_index
		@unit_table.each do |id, data|
			@indices[:name][data[:name]] = id
		end
	end

	def generate_full_indices

	end

	def generate_ngnt_links
		body = Nokogiri::HTML(@agent.get(URI_NGNT).body)
		scrap_ngnt_links_on URI_NGNT
		body.xpath('//*/ul[1]/dd/a/@href')[1..-1].each do |nav|
			scrap_ngnt_links_on URI.join(URI_NGNT, nav.text)
		end

		File.open(LINK_FILE, 'wb') { |f| f.write @links.to_msgpack}
		return self
	end

	def merge_wikia_data _h
		_h.each do |category, data|
			data.each do |type, units|
				units.each do |unit_name|
					unit_id = @indices[:name][unit_name]

					if unit_id == nil
						puts "WARNING: Missing #{unit_name} index on #{category} > #{type}"
						next
					end
					@unit_table[unit_id][category] = type
				end
			end
		end
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
				ls_type: 		nil,
				evolution: 		nil,
				used_by: 		nil,
				attacks: 		nil,
			}

			@links[col[0].to_i] = row.xpath('td[4]/a/@href').text
		end

		return self
	end

	def parse_ngnt_pages _h = {} #_links = nil
		iteration_count = 0

		(_h[:links] ||= @links).each do |id, rel_url|
			iteration_count += 1
			url = URI.join(URI_NGNT, rel_url)
			ap url
			break if _h[:limit] != nil and iteration_count == _h[:limit]

			body = Nokogiri::HTML(@agent.get(url).body)

			evo_chain = Array.new
			req_zel = nil
			req_units = Hash.new
			body.xpath('//*/table[@class="units evolution"]/tbody').each do |row|
				evo_chain = 
					row.xpath('tr/td[@class="unit--number"]').map { |x| x.text.to_i }
			end

			body.xpath('//*/div[@class="large-12 columns"]/ul/li').each do |req|
				if req.text =~ /([\,\d]+) zel/i
					req_zel = $1.gsub(/\,/, '').to_i
				else
					req.xpath('a[1]/@href').text =~ /(\d+)/
					req_units[$1.to_i] = req.text.split("\u00D7")[-1].to_i
				end
			end

			last = evo_chain.length - 1
			(0..last).each do |i|
				@unit_table[evo_chain[i]] ||= Hash.new
				next unless @unit_table[evo_chain[i]][:evolution] == nil
				@unit_table[evo_chain[i]][:evolution] = {
					pre: 			(i-1<0    ? nil : evo_chain[i-1]),
					post: 			(i+1>last ? nil : evo_chain[i+1]),
					requirement: 	nil,
				}
			end

			@unit_table[id][:evolution][:requirement] = {
				zel: 		req_zel,
				units: 		req_units.dup
			} if evo_chain.length > 0

			body.xpath('//*/table[@class="units"]/tbody').each do |usage|
				@unit_table[id] ||= Hash.new
				@unit_table[id][:used_by] = 
					usage.xpath('tr/td[@class="unit--number"]').map do |x|
						{ x.text.to_i => nil }
					end
			end
		end

		return self
	end

	def fetch_wikia_unit_hit_counts
		uhc_url = URI.join(URI_WIKIA, 'Unit_Hit_Counts')
		body = Nokogiri::HTML(@agent.get(uhc_url).body)
		body.xpath('//*/div[@id="mw-content-text"]/table/tr')[2..-1].each do |row|
			col = row.xpath('td').map { |x| x.text }
			id = col[0].to_i
			name = col[1].strip

			if not(name =~ /unreleased/i) and name != @unit_table[id][:name]
				@unit_table[id][:name] = name
			end

			@unit_table[id][:attacks] = {
				normal: 		col[2].to_i == 0 ? nil : col[2].to_i,
				bb: 			col[3].to_i == 0 ? nil : col[3].to_i,
				sbb: 			col[4].to_i == 0 ? nil : col[4].to_i,
			}
		end

		return self
	end

	def fetch_wikia_extra_categories
		bb_types = parse_wikia_category_list({
			heal: 'BB:Heal', offensive: 'BB:Offense', support: 'BB:Support'
		})

		ls_types = parse_wikia_category_list({
			attack: 			'LS:Attack',
			brave_burst: 		'LS:Brave_Burst',
			defense: 			'LS:Defense',
			hit_points: 		'LS:Hit_Points',
			karma: 				'LS:Karma',
			recovery: 			'LS:Recovery',
			zel: 				'LS:Zel',
		})

		return { bb_type: bb_types, ls_type: ls_types }
	end

	def parse_wikia_category_list _categories
		h = Hash.new
		_categories.each do |category, url|
			h[category] = Array.new
			category_url = URI.join(URI_WIKIA, "/Category:#{url}")
			body = Nokogiri::HTML(@agent.get(category_url).body)

			(body.xpath('//*/div[@id="mw-pages"]/div/ul/li') +
			 body.search('td ul li')).each do |r|
				h[category].push r.text
			end
		end

		return h
	end
end