//
//  ContentView.swift
//  HNPlus
//
//  Created by Ashley Newman on 6/3/23.
//

import SwiftUI
import SwiftSoup
import HTML2Markdown

struct ListItem {
    var id: Int
    var title: String
    var link: String
}

struct ContentView: View {
    @State private var listData: [ListItem] = []
    @State private var isDataLoaded = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(listData, id: \.self.id) { item in
                    NavigationLink(destination: PostView(id: item.id, title: item.title, link: item.link)) {
                        Text(item.title)
                    }
                }
            }.refreshable {
                getData();
            }.onAppear() {
                if !isDataLoaded {
                    getData();
                    isDataLoaded = true
                }
            }.navigationTitle("Feed")
        }
    }
    
    func getData() {
        let url = URL(string: "https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty")!
        
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let error = error {
                print("Error: \(error)")
            } else if let data = data {
                let str = String(data: data, encoding: .utf8)
                print("Received data:\n\(str ?? "")")
                
                do {
                    if let jsonArray = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as? [Int]
                    {
                        let first20ids = Array(jsonArray.prefix(20))
                        listData = Array(repeating: ListItem(id: 0, title: "", link: ""), count: first20ids.count)
                        for (index, id) in first20ids.enumerated() {
                            let storyURL = URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json?print=pretty")!
                            let storyTask = URLSession.shared.dataTask(with: storyURL) { (data, response, error) in
                                if let error = error {
                                    print("Error: \(error)")
                                } else if let data = data {
                                    do {
                                        if let json = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as? [String: Any] {
                                            print("Story: \(json)")
                                            if let title = json["title"] as? String {
                                                listData[index].title = title
                                            }
                                            if let url = json["url"] as? String {
                                                listData[index].link = url
                                            }
                                            if let id = json["id"] as? Int {
                                                listData[index].id = id
                                            }
                                        } else {
                                            print("bad json")
                                        }
                                    } catch let error as NSError {
                                        print(error)
                                    }
                                }
                            }
                            storyTask.resume()
                        }
                    } else {
                        print("bad json")
                    }
                } catch let error as NSError {
                    print(error)
                }
            }
        }
        task.resume()
    }
}

struct HNPost: Codable {
    let kids: [Int]?
}

struct HNComment: Codable {
    let id: Int
    var text: String
    let by: String
    let time: Double
}


struct PostView: View {
    let id: Int
    let title: String
    let link: String
    @State private var hnComments: [HNComment] = []
    @State private var hiddenComments = Set<Int>()
    
    var body: some View {
        let dateFormatter = RelativeDateTimeFormatter()
        dateFormatter.unitsStyle = .full
        
        return VStack {
            Link(title, destination: URL(string: link)!)
            ScrollView {
                ForEach(hnComments, id: \.self.id) { item in
                    VStack {
                        HStack {
                            Text(item.by)
                            Spacer()
                            Text(dateFormatter.localizedString(for: Date(timeIntervalSince1970: item.time), relativeTo: Date()))
                        }.padding(.bottom, 2).opacity(0.5)
                        if (!hiddenComments.contains(item.id)) {
                            Text(.init(item.text))
                        }
                    }
                    .background(Color(.systemBackground)) // this makes the VStack tappable
                    .foregroundColor(Color.primary)
                    .padding(.leading, 10)
                    .padding(.trailing, 10)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    .overlay(
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))  // Set the border color here
                            .frame(height: 1),
                        alignment: .bottom
                    )
                    .frame(width: .infinity)
                    .gesture(
                        TapGesture()
                            .onEnded { _ in
                                if (hiddenComments.contains(item.id)) {
                                    hiddenComments.remove(item.id)
                                }
                                else {
                                    hiddenComments.insert(item.id)
                                }
                            }
                    )
                    
                }
            }
        }.onAppear() {
            fetchComments()
        }.navigationBarTitle("", displayMode: .inline)
    }
    
    func fetchComments() {
        let postUrl = URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json?print=pretty")!
        
        let task = URLSession.shared.dataTask(with: postUrl) { (data, _, error) in
            if let error = error {
                print("Error fetching post: \(error)")
            } else if let data = data {
                let decoder = JSONDecoder()
                if let post = try? decoder.decode(HNPost.self, from: data),
                   let commentIds = post.kids {
                    var comments = [Int: HNComment]() // Store comments in a dictionary with their id as key
                    let group = DispatchGroup()
                    for commentId in commentIds {
                        group.enter()
                        let commentUrl = URL(string: "https://hacker-news.firebaseio.com/v0/item/\(commentId).json?print=pretty")!
                        let commentTask = URLSession.shared.dataTask(with: commentUrl) { (data, _, error) in
                            if let error = error {
                                print("Error fetching comment: \(error)")
                            } else if let data = data,
                                      var comment = try? decoder.decode(HNComment.self, from: data) {
                                do {
                                    let decoded = try Entities.unescape(comment.text)
                                    comment.text = decoded.replacingOccurrences(of: "<p>", with: "&NewLine;&NewLine;").replacingOccurrences(of: "</p>", with: "&NewLine;&NewLine;")
                                    
                                    let dom = try HTMLParser().parse(html: comment.text)
                                    comment.text = dom.toMarkdown()
                                    
                                    comments[commentId] = comment // Store the fetched comment in the dictionary
                                }
                                catch {
                                    print("error")
                                }
                                
                            }
                            group.leave()
                        }
                        commentTask.resume()
                    }
                    group.notify(queue: .main) {
                        // Sort the comments according to the order in the `kids` array
                        let sortedComments = commentIds.compactMap { comments[$0] }
                        hnComments = sortedComments
                    }
                }
            }
        }
        task.resume()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        PostView(id: 36185218, title: "A birder's quest to see 10k species", link: "https://news.ycombinator.com/item?id=36185218")
    }
}
