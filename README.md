# Gorget

![Build Status]( https://github.com/longoria/Gorget/actions/workflows/swift.yml/badge.svg)

Gorget is a Swift library enabling content hashing of static asset files for websites 

This library is primarily meant for embedding in other Swift programs and applications.
There is no command-line tool or executable provided yet.

## What problem is this solving?

When serving static assets for a website behind a content delivery network (CDN) the default is for requests to be cached if the request URL is the same.
This is a feature, as the content will only be fetched once if cached by a client.
This is a bug if new content is published at the same URL, as the client will never reach it. 

Instead of manual cache invalidations, or complicated workflows, the web world sometimes processes file names to reflect their content, a content hash. This way the cache automatically hits for files not updated, and misses for fresh content.

## How does Gorget solve this in Swift?

Gorget will:
1. Take a directory of static website files
2. Revise names based on their content
3. Update files referencing the new file names
4. Output files to a new directory (`Gorget_Revised`)

It's API is simple:
```swift
let plan = await Gorget.live.generateRevisionPlan(
  for: myLocalWebsiteAssetsDirectoryURL,
  skippingRenamingOf: ["my-files-not-to-rename.html", "dont-rename.rss"]
)

// To interrogate what it will do, you can print out the plan description
print(plan.description)

// Once you'd like to actually perform the plan
do {
    try await plan.execute()
} catch {
    // handle error
}
```

*Note*: By convention, this library assumes that manifest types of files (such as `index.html` and XML/RSS feeds) are set to not cache, so allows to skipping the renaming of those files.

## Installation

You can add Dependencies to an Xcode project by adding it to your project as a package.

> https://github.com/longoria/Gorget

If you want to use Gorget in a [SwiftPM](https://swift.org/package-manager/) project, add it to your `Package.swift`:

``` swift
dependencies: [
  .package(url: "https://github.com/longoria/Gorget", from: "0.1.0")
]
```

And then adding the product to any target that needs access to the library:

```swift
.product(name: "Gorget", package: "Gorget"),
```

## Some details

### Name replacing in text content

Currently, when content is updated to reflect new revised names, it will replace even mentions to the same names in written and all content.
This should normally be OK, but if overly ambitous replaces end up being a common scenario, a more sophisticated file-type-based RegEx will be implemented.
A short-term workaround could use entity escaping for written content in HTML.

### Non-cryptographic Hashing

To optimize for speed, and since security isn't a requirement, this library uses the `SHA1` algorithm provided by Apple's [CryptoKit](https://developer.apple.com/documentation/cryptokit/insecure/sha1).

Once a stable, up-to-date Swift wrapper for [xxHash](https://cyan4973.github.io/xxHash/) has been published, I plan to switch to that.

### Speed

I haven't stressed test this for site's with a large amount of content. As I grow my own website content, or as I find bottlenecks, I will improve the performance. 
