#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "TestResources.hpp"
#import "FileInfo.hpp"

@interface FileInfoTests : XCTestCase

@end

@implementation FileInfoTests

- (void)testLoading {
  auto fi1 = SF2::FileInfo("a.b");
  XCTAssertFalse(fi1.load());
  auto url = [TestResources getResourceUrl:0];
  auto fi2 = SF2::FileInfo(url.path.UTF8String);
  XCTAssertTrue(fi2.load());
}

- (void)testEmbeddedContent0 {
  auto url = [TestResources getResourceUrl: 0];
  auto fi1 = SF2::FileInfo(url.path.UTF8String);
  fi1.load();
  XCTAssertTrue(std::string("Free Font GM Ver. 3.2") == fi1.embeddedName());
  XCTAssertTrue(std::string("") == fi1.embeddedAuthor());
  XCTAssertTrue(std::string("") == fi1.embeddedComment());
  XCTAssertTrue(std::string("") == fi1.embeddedCopyright());
}

- (void)testEmbeddedContent1 {
  auto url = [TestResources getResourceUrl: 1];
  auto fi1 = SF2::FileInfo(url.path.UTF8String);
  fi1.load();
  XCTAssertTrue(std::string("GeneralUser GS MuseScore version 1.442") == fi1.embeddedName());
  XCTAssertTrue(std::string("S. Christian Collins") == fi1.embeddedAuthor());
  XCTAssertTrue(std::string("***     License v2.0    ***____** License of the complete work **__You may use GeneralUser GS without restriction for your own music creation, private or commercial.  This SoundFont bank is provided to the community free of charge.  Please feel free to use it in your software projects, and to modify the SoundFont bank or its packaging to suit your needs.____** License of contained samples **__GeneralUser GS inherits the usage rights of the samples contained within, all of which allow full use in music production, including the ability to make profit from musical recordings created with GeneralUser GS.____Many of the samples are original, but some were taken from other banks freely (and legally) available on the Internet from various SoundFont websites.  Because GeneralUser GS originated as a personal project with no intention for publication, I cannot be 100% sure where all of the samples originated, although I do know that none of them came from commercially published SoundFont packages or sample CDs.  Regardless, many \"free\" SoundFonts available on the web may indeed contain samples of questionable origin.  My understanding of the copyrights of all samples is only as good as the information provided by the original sources. If you become aware of any restricted samples being used in GeneralUser GS, please let me know so I can replace them.____This uncertainty may concern you if you intend to use GeneralUser GS in a commercial software product.  That being said, I have never received any complaint regarding sample ownership since I published the original GeneralUser GS back in 2000, and as far as I am aware, neither have any of the companies creating commercial software products using GeneralUser GS.____** More info **__If you plan to feature GeneralUser GS on your own website, please do not link directly to my download files.  Either link to my website, or provide your own local copy instead.____I hope you enjoy GeneralUser GS!  This SoundFont bank is the product of many years of hard work.____You can find updates to GeneralUser GS and more of my SoundFonts at:__http://www.schristiancollins.com____I can be reached at: s_chriscollins@hotmail.com.____Thank you!__-Chris") == fi1.embeddedComment());
  XCTAssertTrue(std::string("2012 by S. Christian Collins") == fi1.embeddedCopyright());
}

- (void)testEmbeddedContent2 {
  auto url = [TestResources getResourceUrl: 2];
  auto fi1 = SF2::FileInfo(url.path.UTF8String);
  fi1.load();
  XCTAssertTrue(std::string("User Bank") == fi1.embeddedName());
  XCTAssertTrue(std::string("Vienna Master") == fi1.embeddedAuthor());
  XCTAssertTrue(std::string("Comments Not Present") == fi1.embeddedComment());
  XCTAssertTrue(std::string("Copyright Information Not Present") == fi1.embeddedCopyright());
}

- (void)testPresetInfo {
  auto url = [TestResources getResourceUrl: 0];
  auto fi1 = SF2::FileInfo(url.path.UTF8String);
  fi1.load();
  XCTAssertEqual(235, fi1.getPresets().size());
  auto presetInfo = fi1.getPresets()[0];
  XCTAssertTrue(std::string("Piano 1") == presetInfo.name());
  XCTAssertEqual(0, presetInfo.bank());
  XCTAssertEqual(0, presetInfo.program());

  presetInfo = fi1.getPresets()[2];
  XCTAssertTrue(std::string("Piano 3") == presetInfo.name());
  XCTAssertEqual(0, presetInfo.bank());
  XCTAssertEqual(2, presetInfo.program());

  presetInfo = fi1.getPresets()[234];
  XCTAssertTrue(std::string("SFX") == presetInfo.name());
  XCTAssertEqual(128, presetInfo.bank());
  XCTAssertEqual(56, presetInfo.program());
}

@end
