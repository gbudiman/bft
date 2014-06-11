require '../lib/Scrapper.rb'

describe Scrapper do
	before :all do
		@scrapper = Scrapper.new
	end

	it { is_expected.to respond_to :unit_table }
	it { is_expected.to respond_to :index }

	context 'debugging utility' do
		it 'should allow singular unit ID query' do
			@scrapper.debug 171
			expect(@scrapper.unit_table[171]).not_to be nil
		end

		it 'should allow multiple unit ID query' do
			@scrapper.debug *5..8, 339
			[5,6,7,8,339].each do |id|
				expect(@scrapper.unit_table[id]).not_to be nil
			end
		end
	end

	context 'after scrapping' do
		before :all do
			@scrapper.scrap
			@link_file_path = File.join('..', 'lib', 'links.mp')
		end

		it 'should return non-zero length unit_table' do
			expect(@scrapper.unit_table.length).to be > 0
		end

		it 'should not have undefined unit ID' do
			@scrapper.unit_table.keys.each do |key|
				expect(key).not_to be nil
			end
		end

		it 'should generate links.mp file' do
			expect(File.exists? @link_file_path).to be true
		end

		it 'links.mp file should be de-serialize-able and non-empty' do
			MessagePack.unpack(IO.binread @link_file_path) do |f|
				expect(f.is_a? Hash).to be true
				expect(f.length).to be > 0
			end
		end

		it 'should be dump-able' do
			@scrapper.to_s
		end
	end
end