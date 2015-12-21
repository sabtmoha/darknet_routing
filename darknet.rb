#!/usr/bin/ruby1.8

require 'Qt'
require 'digest/sha1'


def contentToHash content
	hash = (Digest::SHA1.hexdigest content)
	return hash[0,20].upcase
end

def hashToPos hash
	return hash[0,10].hex/(16**10.0), hash[10,10].hex/(16**10.0)
end

def contentToPos content
	return hashToPos( contentToHash content)
end

def distanceHash a, b
	ax, ay = hashToPos a
	bx, by = hashToPos b 
	return Math.sqrt((ax-bx)**2 + (ay-by)**2)
end


class Node

	attr_reader :friends
	attr_accessor :id, :x, :y, :files

	def initialize id
		@id = id

		@x, @y = hashToPos id

		@friends = Hash.new
		@files = Hash.new
	end

	def changeID id
		@id = id

		@x, @y = hashToPos id
	end

	# Euclidean distance
	def distance a
		return distanceHash self.id, a.id
	end

	def chooseSmallWorldFriends nodes, nbFriends, nearbyFriendFactor

		nbFriends = [nodes.size - 1 - @friends.size, nbFriends].min
		nodes = nodes - [self] - @friends.values

		if nearbyFriendFactor == 0
			nbFriends.times do
				node = nodes.choice
				
				self.addFriend node
				node.addFriend self
				nodes.delete node
			end
		else
			nbFriends.times do
				dist = (1.0-(1.0-rand()**(nearbyFriendFactor*2.0))**(1.0/(nearbyFriendFactor*2.0))) * Math.sqrt(2)
				node = nodes.min_by{|node| (self.distance(node) - dist).abs}

				self.addFriend node
				node.addFriend self
				nodes.delete node
			end
		end

	end

	def addFriend node
		@friends[node.id] = node
	end

	def removeAllFriends
		@friends = Hash.new
	end

	# Returns the route to dest without passing through the excludedNodes. If it doesn't exist, returns nil
	def greedyRoute dest, htl = -1, excludedNodes = []
		if @friends.has_key? dest
			return [[self.id, dest]]
		end

		# get friends ordered by proximity with destination
		bestFriends = (@friends.values - excludedNodes - [self]).sort_by{|n| distanceHash(dest,n.id)}
		
		route = []
		friend = nil

		while route.empty? and not bestFriends.empty?
			friend = bestFriends.shift
			
			yield [[self.id, friend.id]]
			
			if htl == 0
				return [[self.id, friend.id]]
			else
				route = friend.greedyRoute(dest, htl-1, excludedNodes.push(self)){|route| yield route.push [self.id, friend.id]}
			end
		end

		if not route.empty?
			return route.push [self.id, friend.id]
		else
			return []
		end

	end

	def randomRoute dest, htl = -1, excludedNodes = []
		return []
		if @friends.has_key? dest
			return [[self.id, dest]]
		end

		# get friends ordered randomly
		bestFriends = (@friends.values - excludedNodes - [self]).shuffle
		
		route = []
		friend = nil

		while route.empty? and not bestFriends.empty?
			friend = bestFriends.shift
			yield [[self.id, friend.id]]

			if htl == 0
				return [[self.id, friend.id]]
			else
				route = friend.randomRoute(dest, htl-1, excludedNodes.push(self)){|route| yield route.push [self.id, friend.id]}
			end
		end

		if not route.empty?
			return route.push([self.id, friend.id])
		else
			return []
		end
		
	end

	def swap n
		temp = @x
		@x = n.x
		n.x = temp
		
		temp = @y
		@y = n.y
		n.y = temp

		temp = @id
		@id = n.id
		n.id = temp

		temp = @files
		@files = n.files
		n.files = temp

	end
	
	def logSum n
		sum = 0.0
		@friends.each_value do |friend|
			if friend.x == n.x and friend.y == n.y # if the node n is one of our friend
				sum += Math.log((n.x - @x).abs + (n.y - @y).abs)
			else
				sum += Math.log((n.x - friend.x).abs + (n.y - friend.y).abs)
			end
		end
		return sum
	end

	def unlink
		@friends.each_value do |friend|
			friend.friends.delete self.id
		end
	end

	def addFile content
		@files[contentToHash(content)] = content
	end

end


class Darknet

	attr_reader :nodes, :randomRoute, :greedyRoute, :selectedNode, :nearbyFriendFactor, :nbFriends, :stats, :selectedHash
	attr_accessor :deepness
	def initialize

		# The list of nodes
		@nodes = Hash.new

		# The last routes that have been computed
		@greedyRoute = Array.new
		@randomRoute = Array.new
		@selectedNode = nil

		# The nearby friend factor determine how nodes choose their friends.
		# The bigger the factor is, the more the proximity will be an important factor.
		# Example:
		# 0 ->		the odds of being friend with a node is the same for every node
		# 1 ->		the odds of being friend with a node is inversely proportional to the distance between them
		# 2..inf ->	the odds of being friend with a node is based on a polynomial formula of degree n
		# the exact formula is based on the circle formula (which is x² + y² = 1) :
		# probabilyOfBeingFriend = 1 - (1 - (distance - 1) ** n) ** (1/n)
		@nearbyFriendFactor = 2

		# The number of friends of each nodes
		@nbFriends = 3

		# Number of values per bar
		@nbValuesPerBar = 10
		@stats = Array.new

		@selectedHash = contentToHash ""

		@nextNodeID = 0

		2.times{addNode}

		@selectedNode = @nodes.values.choice

		@deepness = 15


	end # def initialize


	# Remove friends from nodes with too many friends without leaving nodes with too few friends
	def cleanNetwork
		# TODO implement
	end #def cleanNetwork

	def addNode
		newNode = Node.new contentToHash("node#{@nextNodeID}")
		@nextNodeID += 1
		
		@nodes[newNode.id] = newNode
	    		
		newNode.chooseSmallWorldFriends @nodes.values, [@nodes.size-1, @nbFriends].min, @nearbyFriendFactor

		cleanNetwork
	end # def addNode

	def recomputeFriends
		@greedyRoute = Array.new
		@randomRoute = Array.new

		@nodes.each_value do |node|
			node.removeAllFriends
		end

		@nodes.each_value do |node|
			node.chooseSmallWorldFriends @nodes.values, [@nodes.size-1, @nbFriends].min, @nearbyFriendFactor
		end

		cleanNetwork

		computeRoutes
	end

	def recomputePositions
		@nodes.each_value do |node|
			oldID = node.id
			node.changeID(contentToHash rand.to_s)
			@nodes[node.id] = node
			@nodes.delete oldID
		end

		computeRoutes
	end


	def changeNearbyFriendFactor r
		@nearbyFriendFactor = r
		recomputeFriends
	end # def changenearbyFriendFactor


	def changeNbFriends n
		@nbFriends = n
		recomputeFriends
	end # def changeNbFriends

	def changeNbNode n
		if n > @nodes.size
			(n - @nodes.size).times do
				self.addNode
			end
		elsif n < @nodes.size
			@nodes.keys[n, @nodes.size-n].each do |node|
				if @selectedNode.id == node
					@selectedNode = @nodes[(@nodes.keys - [node]).choice]
				end
				nodes[node].unlink
				@nodes.delete node
			end
		end
	end # def changeNbFriends


	def computeRoutes
		@greedyRoute = @selectedNode.greedyRoute(@selectedHash, @deepness){}
		@randomRoute = @selectedNode.randomRoute(@selectedHash, @deepness){}

		if not getFile(@selectedHash).empty?
			return true
		else
			return false
		end
	end

	def computeStats
		distances = @nodes.values.map{|node| node.friends.values.map{|friend| [node,friend]}}.flatten(1).select{|route| route[0].id < route[1].id}.map{|route| route[0].distance route[1]}

		@stats = Array.new
		nbBars = (distances.size / @nbValuesPerBar).to_i
		nbBars.times do |barNumber|
			range = Math.sqrt(2) / nbBars * barNumber, Math.sqrt(2) / nbBars * (barNumber + 1)

			@stats[barNumber] = distances.count{|distance| distance > range[0] and distance < range[1]}
		end

	end

	def swapRandomNodes
		(100*@nodes.size).times do
			nodeA, nodeB = @nodes.values.choice, @nodes.values.choice
			prob = Math.exp(-2 * (nodeA.logSum(nodeB) + nodeB.logSum(nodeA) - nodeA.logSum(nodeA) - nodeB.logSum(nodeB)))

			if rand < prob
			 	nodeA.swap(nodeB)
				 	@nodes.delete nodeA.id
				 	@nodes.delete nodeB.id
				 	@nodes[nodeA.id] = nodeA
				 	@nodes[nodeB.id] = nodeB
			end
		end


		computeRoutes

	end

	def putFile content
		@greedyRoute = @selectedNode.greedyRoute(contentToHash(content), @deepness) {}
		@randomRoute = @selectedNode.randomRoute(contentToHash(content), @deepness){}

		@greedyRoute.each do |link|
			@nodes[link[1]].addFile(content)
		end
	end

	def getFile hash
		@greedyRoute = @selectedNode.greedyRoute(hash, @deepness) {}
		@greedyRoute.each do |link|
			if @nodes[link[1]].files.has_key?(hash)
				return @nodes[link[1]].files[hash]
			end
		end
		return ""
	end

	def changeHash hash
		@selectedHash = hash[0,20].upcase+'0'*(hash.size<20 ? 20-hash.size : 0)
		computeRoutes
	end

	def selectRandomNode
		@selectedNode = @nodes.values.choice
	end
end

class MainWindow < Qt::Widget

 	signals 'valueChanged(int)'
 	signals :clicked
 	signals :textChanged
 	signals 'textChanged(QString)'
 	signals 'resizeEvent(QResizeEvent *)'
  	slots 'changeNearbyFriendFactor(int)'
  	slots 'changeNbFriends(int)'
  	slots 'changeNbNode(int)'
  	slots :recomputeFriendLinks
  	slots :randomizePositions
  	slots :selectRandomNode
  	slots :swap
  	slots :reset
  	slots :putButton
  	slots :getButton
  	slots :fileChanged
  	slots 'resizeBF(QResizeEvent *)'
  	slots 'hashChanged(QString)'
  	slots 'changeDeepness(int)'
  	slots :clearButton


    def initialize
        super

        @darknet = Darknet.new

        resize 1024, 640
        setWindowTitle "Darknet Demo"

        @spinBoxNFF = Qt::SpinBox.new
        @spinBoxNFF.setMinimum 0
        @spinBoxNFF.setMaximum 10
        @spinBoxNFF.setValue @darknet.nearbyFriendFactor
        connect(@spinBoxNFF, SIGNAL('valueChanged(int)'), self, SLOT('changeNearbyFriendFactor(int)'))

		@spinBoxNF = Qt::SpinBox.new
        @spinBoxNF.setMinimum 0
        @spinBoxNF.setMaximum 30
        @spinBoxNF.setValue @darknet.nbFriends
        connect(@spinBoxNF, SIGNAL('valueChanged(int)'), self, SLOT('changeNbFriends(int)'))

        @spinBoxNN = Qt::SpinBox.new
        @spinBoxNN.setMinimum 2
        @spinBoxNN.setMaximum 999
        @spinBoxNN.setValue @darknet.nodes.size
        connect(@spinBoxNN, SIGNAL('valueChanged(int)'), self, SLOT('changeNbNode(int)'))

        @recomputeFriendLinks = Qt::PushButton.new "Recompute friend links"
        @recomputeFriendLinks.connect(:clicked, self, :recomputeFriendLinks)

        @randomizePositions = Qt::PushButton.new "Randomize nodes positions"
        @randomizePositions.connect(:clicked, self, :randomizePositions)

        @selectRandomNode = Qt::PushButton.new "Select Random Node"
		@selectRandomNode.connect(:clicked, self, :selectRandomNode)

        @swap = Qt::PushButton.new "Swapping (100 times)"
        @swap.connect(:clicked, self, :swap)

        @reset = Qt::PushButton.new "Reset"
        @reset.connect(:clicked, self, :reset)

        @menu1 = Qt::Widget.new
        menu1L = Qt::FormLayout.new
        menu1L.addRow Qt::Label.new("   Network operations:")
		menu1L.addRow Qt::Label.new("Nearby Friend Factor"), @spinBoxNFF
        menu1L.addRow Qt::Label.new("Number of friends"), @spinBoxNF
        menu1L.addRow Qt::Label.new("Number of nodes"), @spinBoxNN
        menu1L.addRow @recomputeFriendLinks
        menu1L.addRow @randomizePositions
        menu1L.addRow @selectRandomNode
        menu1L.addRow @swap
        menu1L.addRow @reset
        @menu1.setLayout menu1L

        @spinBoxDeepness = Qt::SpinBox.new
        @spinBoxDeepness.setMinimum 1
        @spinBoxDeepness.setMaximum 999
        @spinBoxDeepness.setValue @darknet.deepness + 1
        connect(@spinBoxDeepness, SIGNAL('valueChanged(int)'), self, SLOT('changeDeepness(int)'))

        @putButton = Qt::PushButton.new "Put"
        @putButton.connect(:clicked, self, :putButton)
        @putButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))

        @getButton = Qt::PushButton.new "Get"
        @getButton.connect(:clicked, self, :getButton)
        @getButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))

        @clearButton = Qt::PushButton.new "Clear"
        @clearButton.connect(:clicked, self, :clearButton)

       	@lineEdit = Qt::LineEdit.new contentToHash ""
       	@lineEdit.setMaxLength 20
		connect(@lineEdit, SIGNAL('textChanged(QString)'), self, SIGNAL('hashChanged(QString)') )   

        @textEdit = Qt::TextEdit.new
		@textEdit.connect(:textChanged, self, :fileChanged)

        @menu2 = Qt::Widget.new
        menu2L = Qt::FormLayout.new
        menu2L.addRow Qt::Splitter.new
        menu2L.addRow Qt::Label.new("   File operations:")
        menu2L.addRow @lineEdit
        menu2L.addRow @textEdit
        menu2L.addRow Qt::Label.new("Deepness"), @spinBoxDeepness
        tmp = Qt::HBoxLayout.new
        tmp.addWidget @putButton
        tmp.addWidget @getButton
        tmp.addWidget @clearButton

        menu2L.addRow tmp
        @menu2.setLayout menu2L

		@menu = Qt::Widget.new
		@menuL = Qt::VBoxLayout.new
		@menuL.addWidget @menu1
		@menuL.addWidget @menu2
		@menu.setLayout @menuL


        @networkWidget = NetworkWidget.new
        @networkWidget.darknet = @darknet

        @stats = StatsWidget.new
		@stats.darknet = @darknet

        layout = Qt::HBoxLayout.new
        layout.addWidget @menu
        layout.addWidget @networkWidget
        layout.addWidget @stats
        setLayout layout

        @networkWidget.setFocusPolicy Qt::StrongFocus
        @menu.setFixedWidth 200
        @stats.setFixedWidth 150

        connect(self, SIGNAL('resizeEvent(QResizeEvent *)'), self, SLOT('resizeBF(QResizeEvent *)'))
        resizeBF nil
        show
    end

    def resizeBF e
    	@networkWidget.setFixedWidth self.size().width()-200-150-40
    end

    def changeNearbyFriendFactor r
    	@darknet.changeNearbyFriendFactor r
    	@darknet.computeStats
    	self.update
    end

    def changeNbFriends n
    	@darknet.changeNbFriends n
    	@darknet.computeStats
    	self.update
    end

    def changeNbNode n
    	@darknet.changeNbNode n
    	@darknet.computeStats
    	if @darknet.computeRoutes
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	else
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	end

    	if @darknet.greedyRoute.empty?
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	else
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	end
    	self.update
    end

    def recomputeFriendLinks
    	@darknet.recomputeFriends
		self.update
    end

    def randomizePositions
    	@darknet.recomputePositions
    	@darknet.selectRandomNode
    	if @darknet.computeRoutes
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	else
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	end

    	if @darknet.greedyRoute.empty?
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	else
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	end
    	@darknet.computeStats
    	self.update
    end

    def selectRandomNode
    	@darknet.selectRandomNode
    	if @darknet.computeRoutes
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	else
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	end

    	if @darknet.greedyRoute.empty?
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	else
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	end

		self.update
    end

    def swap
    	@darknet.swapRandomNodes
		@darknet.computeStats
    	self.update	
    end

	def reset
		@darknet = Darknet.new
		@networkWidget.darknet = @darknet
		@stats.darknet = @darknet
		@darknet.changeNearbyFriendFactor @spinBoxNFF.value
		@darknet.changeNbFriends @spinBoxNF.value
		@darknet.changeNbNode @spinBoxNN.value
		@darknet.deepness = @spinBoxDeepness.value - 1
		if @darknet.computeRoutes
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	else
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	end

    	if @darknet.greedyRoute.empty?
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	else
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	end
		@darknet.computeStats
		self.update
	end


	def putButton
		if @textEdit.plainText.empty?
			return
		end

		@darknet.putFile(@textEdit.plainText)
		clearButton

		if @darknet.computeRoutes
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	else
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	end

    	if @darknet.greedyRoute.empty?
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	else
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	end

		self.update
	end

	def getButton
			if not @textEdit.plainText.empty?
				return
			end
			
			hash = @lineEdit.text
			file = @darknet.getFile(hash[0,20].upcase+'0'*(hash.size<20 ? 20-hash.size : 0))

			if not file.empty?
				@textEdit.setText file
			end
			self.update
	end

	def clearButton
		tmp = @lineEdit.text
		@textEdit.setText ""
		@lineEdit.setText tmp
	end

	def fileChanged
			@lineEdit.setText contentToHash @textEdit.plainText
	end

	def hashChanged hash
			@darknet.changeHash hash
			self.update
	end

 	def changeDeepness d
 		@darknet.deepness = d-1
 		if @darknet.computeRoutes
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	else
    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	end

    	if @darknet.greedyRoute.empty?
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
    	else
    		@putButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
    	end
 		self.update
	end

    def keyPressEvent e
    	case e.key

		    when Qt::Key_Escape
		    	$qApp.quit

	    	when Qt::Key_N
	    		@darknet.addNode
	    		@darknet.computeStats
	    		self.update

		    when Qt::Key_F
		    	recomputeFriendLinks

		    when Qt::Key_P
		    	randomizePositions

		    when Qt::Key_R
		    	if @darknet.computeRoutes
		    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(0, 200, 0)))
		    	else
		    		@getButton.setPalette(Qt::Palette.new(Qt::Color.new(200, 0, 0)))
		    	end

		    when Qt::Key_D
		    	reset

		    when Qt::Key_S
				swap	

	    end
    end

end

class NetworkWidget < Qt::Widget
	
	attr_accessor :darknet

	def initialize
		super
	end

	def paintEvent event

        painter = Qt::Painter.new self
        painter.setRenderHint Qt::Painter::Antialiasing

		h, w = self.size().height(), self.size().width()

		nodeSize = 10

		# Paint friends links

		painter.setPen Qt::Color::new 100, 100, 255

		@darknet.nodes.each_value do |node|
			node.friends.each_value do |friend|
 				painter.drawLine node.x*w, node.y*h, friend.x*w, friend.y*h
 			end
 		end

 		# Paint random route

 
		pen = Qt::Pen.new
 		pen.setColor Qt::Color::new 0, 255, 0
 		pen.setWidth 4
 		painter.setPen pen 

		@darknet.randomRoute.each do |link|
			link=[@darknet.nodes[link[0]],@darknet.nodes[link[1]]]
 			painter.drawLine link[0].x*w, link[0].y*h, link[1].x*w, link[1].y*h
 		end

 		# Paint greedy route

 		pen = Qt::Pen.new
 		pen.setColor Qt::Color::new 255, 0, 0
 		pen.setWidth 2
 		painter.setPen pen 

		@darknet.greedyRoute.each do |link|
			link=[@darknet.nodes[link[0]],@darknet.nodes[link[1]]]
 			painter.drawLine link[0].x*w, link[0].y*h, link[1].x*w, link[1].y*h
 		end

 		# Paint nodes

		@darknet.nodes.each_value do |node|
			if node.files.has_key?(@darknet.selectedHash)
				painter.setPen Qt::Color::new 255, 255, 255
				painter.setBrush Qt::Brush.new Qt::Color::new 0, 255, 0
			elsif  not node.files.empty?
				painter.setPen Qt::Color::new 0, 255, 0
				painter.setBrush Qt::Brush.new Qt::Color::new 100, 100, 100
			else
				painter.setPen Qt::Color::new 255, 255, 255
				painter.setBrush Qt::Brush.new Qt::Color::new 100, 100, 100
			end

			 painter.drawEllipse  node.x*w-nodeSize/2, node.y*h-nodeSize/2, nodeSize, nodeSize
		end

		# Paint selected node

		painter.setPen Qt::Color::new 255, 255, 255
		painter.setBrush Qt::Brush.new Qt::Color::new 255, 0, 0

		painter.drawEllipse @darknet.selectedNode.x*w-nodeSize, @darknet.selectedNode.y*h-nodeSize, nodeSize*2, nodeSize*2


		painter.setPen Qt::Color::new 255, 255, 255
		painter.setBrush Qt::Brush.new Qt::Color::new 0, 255, 0

		x, y = hashToPos @darknet.selectedHash
		painter.drawEllipse x*w-nodeSize, y*h-nodeSize, nodeSize*2, nodeSize*2

        painter.end
    end

end

class StatsWidget < Qt::Widget
	
	
	attr_accessor :darknet

	def initialize
		super
	end

	def paintEvent event

		if @darknet.stats.empty?
			return
		end

		painter = Qt::Painter.new self

		h, w = self.size().height(), self.size().width()


		max = @darknet.stats.max

		nbBars = darknet.stats.size
		nbBars.times do |barNumber|
			greyShade = (50 + 150.to_f / nbBars * barNumber).to_i
			painter.setPen Qt::Color::new greyShade, greyShade, greyShade
			painter.setBrush Qt::Brush.new Qt::Color::new greyShade, greyShade, greyShade
			painter.drawRect 0,h.to_f / nbBars*barNumber,@darknet.stats[barNumber].to_f / max * w, h.to_f/nbBars
		end

		painter.end

	end
end


app = Qt::Application.new ARGV
MainWindow.new
app.exec
