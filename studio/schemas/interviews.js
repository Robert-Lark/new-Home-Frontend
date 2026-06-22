export default {
  name: "interview",
  title: "Interviews",
  type: "document",
  fields: [
    {
        name: "cat",
        title: "Cat number of mix",
        type: "number",
      },
    {
      name: "name",
      title: "Name of Artist",
      type: "string",
    },
    {
      name: "slug",
      title: "Slug",
      type: "slug",
      options: {
        source: "name",
        maxLength: 100,
      },
    },
    {
      name: "date",
      title: "Air date",
      type: "date",
      description:
        "Original broadcast/publish date. Drives the Archive calendar; the site falls back to the document's creation date when unset.",
    },
    {
      name: "image",
      title: "Image",
      type: "image",
      options: {
        hotspot: true,
      },
    },
    {
      name: "url",
      title: "URL of mix",
      type: "string",
    },
    {
      name: "description",
      title: "Description",
      type: "text",
      description: "Tell us a bit about this artist",
    },
      {
        name: "question1",
        title: "Question1",
        type: "string",
      },
      {
        name: "style1",
        title: "Style1",
        type: "string",
      },
      {
        name: "answer1",
        title: "Answer1",
        type: "text",
      },
      {
        name: "i1",
        title: "Image1",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question2",
        title: "Question2",
        type: "string",
      },
      {
        name: "style2",
        title: "Style2",
        type: "string",
      },
      {
        name: "answer2",
        title: "Answer2",
        type: "text",
      },
      {
        name: "i2",
        title: "Image2",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question3",
        title: "Question3",
        type: "string",
      },
      {
        name: "style3",
        title: "Style3",
        type: "string",
      },
      {
        name: "answer3",
        title: "Answer3",
        type: "text",
      },
      {
        name: "i3",
        title: "Image3",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question4",
        title: "Question4",
        type: "string",
      },
      {
        name: "style4",
        title: "Style4",
        type: "string",
      },
      {
        name: "answer4",
        title: "Answer4",
        type: "text",
      },
      {
        name: "i4",
        title: "Image4",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question5",
        title: "Question5",
        type: "string",
      },
      {
        name: "style5",
        title: "Style5",
        type: "string",
      },
      {
        name: "answer5",
        title: "Answer5",
        type: "text",
      },
      {
        name: "i5",
        title: "Image5",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question6",
        title: "Question6",
        type: "string",
      },
      {
        name: "style6",
        title: "Style6",
        type: "string",
      },
      {
        name: "answer6",
        title: "Answer6",
        type: "text",
      },
      {
        name: "i6",
        title: "Image6",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question7",
        title: "Question7",
        type: "string",
      },
      {
        name: "style7",
        title: "Style7",
        type: "string",
      },
      {
        name: "answer7",
        title: "Answer7",
        type: "text",
      },
      {
        name: "i7",
        title: "Image7",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question8",
        title: "Question8",
        type: "string",
      },
      {
        name: "style8",
        title: "Style8",
        type: "string",
      },
      {
        name: "answer8",
        title: "Answer8",
        type: "text",
      },
      {
        name: "i8",
        title: "Image8",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question9",
        title: "Question9",
        type: "string",
      },
      {
        name: "style9",
        title: "Style9",
        type: "string",
      },
      {
        name: "answer9",
        title: "Answer9",
        type: "text",
      },
      {
        name: "i9",
        title: "Image9",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question10",
        title: "Question10",
        type: "string",
      },
      {
        name: "style10",
        title: "Style10",
        type: "string",
      },
      {
        name: "answer10",
        title: "Answer10",
        type: "text",
      },
      {
        name: "i10",
        title: "Image10",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question11",
        title: "Question11",
        type: "string",
      },
      {
        name: "style11",
        title: "Style11",
        type: "string",
      },
      {
        name: "answer11",
        title: "Answer11",
        type: "text",
      },
      {
        name: "i11",
        title: "Image11",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question12",
        title: "Question12",
        type: "string",
      },
      {
        name: "style12",
        title: "Style12",
        type: "string",
      },
      {
        name: "answer12",
        title: "Answer12",
        type: "text",
      },
      {
        name: "i12",
        title: "Image12",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question13",
        title: "Question13",
        type: "string",
      },
      {
        name: "style13",
        title: "Style13",
        type: "string",
      },
      {
        name: "answer13",
        title: "Answer13",
        type: "text",
      },
      {
        name: "i13",
        title: "Image13",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question14",
        title: "Question14",
        type: "string",
      },
      {
        name: "style14",
        title: "Style14",
        type: "string",
      },
      {
        name: "answer14",
        title: "Answer14",
        type: "text",
      },
      {
        name: "i14",
        title: "Image14",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question15",
        title: "Question15",
        type: "string",
      },
      {
        name: "style15",
        title: "Style15",
        type: "string",
      },
      {
        name: "answer15",
        title: "Answer15",
        type: "text",
      },
      {
        name: "i15",
        title: "Image15",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question16",
        title: "Question16",
        type: "string",
      },
      {
        name: "style16",
        title: "Style16",
        type: "string",
      },
      {
        name: "answer16",
        title: "Answer16",
        type: "text",
      },
      {
        name: "i16",
        title: "Image16",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question17",
        title: "Question17",
        type: "string",
      },
      {
        name: "style17",
        title: "Style17",
        type: "string",
      },
      {
        name: "answer17",
        title: "Answer17",
        type: "text",
      },
      {
        name: "i17",
        title: "Image17",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question18",
        title: "Question18",
        type: "string",
      },
      {
        name: "style18",
        title: "Style18",
        type: "string",
      },
      {
        name: "answer18",
        title: "Answer18",
        type: "text",
      },
      {
        name: "i18",
        title: "Image18",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question19",
        title: "Question19",
        type: "string",
      },
      {
        name: "style19",
        title: "Style19",
        type: "string",
      },
      {
        name: "answer19",
        title: "Answer19",
        type: "text",
      },
      {
        name: "i19",
        title: "Image19",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
      {
        name: "question20",
        title: "Question20",
        type: "string",
      },
      {
        name: "style20",
        title: "Style20",
        type: "string",
      },
      {
        name: "answer20",
        title: "Answer20",
        type: "text",
      },
      {
        name: "i20",
        title: "Image20",
        type: "image",
        options: {
          hotspot: true,
        },  
      },
    {
      name: "label",
      title: "Label(s)",
      type: "array",
      of: [{type: "reference", to: [{type: "label"}]}],
    },
    {
      name: "releases",
      title: "Releases",
      type: "array",
      of: [{type: "reference", to: [{type: "release"}]}],
    },
  ],
  preview: {
    select: {
      name: "name",
    },
    prepare: ({name}) => ({
      title: `${name}`,
    }),
  },
};
